#include <android/log.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <jni.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

#include "zygisk.hpp"

namespace {

constexpr char kTag[] = "FridaMagiskZygisk";
constexpr char kModuleFallback[] = "/data/adb/modules/frida_magisk";
constexpr char kRuntimeBase[] = "/data/local/tmp/frida_magisk";

#if defined(__aarch64__)
constexpr char kAbi[] = "arm64-v8a";
#elif defined(__arm__)
constexpr char kAbi[] = "armeabi-v7a";
#elif defined(__x86_64__)
constexpr char kAbi[] = "x86_64";
#elif defined(__i386__)
constexpr char kAbi[] = "x86";
#else
constexpr char kAbi[] = "unknown";
#endif

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, kTag, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, kTag, __VA_ARGS__)

void copy_string(char *dst, size_t dst_size, const char *src) {
  if (dst_size == 0) return;
  if (src == nullptr) {
    dst[0] = '\0';
    return;
  }
  std::snprintf(dst, dst_size, "%s", src);
}

bool read_fd_path(int fd, char *out, size_t out_size) {
  char link_path[64];
  std::snprintf(link_path, sizeof(link_path), "/proc/self/fd/%d", fd);
  ssize_t len = readlink(link_path, out, out_size - 1);
  if (len <= 0) return false;
  out[len] = '\0';
  return true;
}

bool read_config_value(int dir_fd, const char *key, char *out, size_t out_size) {
  out[0] = '\0';
  int fd = openat(dir_fd, "config.env", O_RDONLY | O_CLOEXEC);
  if (fd < 0) return false;

  char buffer[4096];
  ssize_t len = read(fd, buffer, sizeof(buffer) - 1);
  close(fd);
  if (len <= 0) return false;
  buffer[len] = '\0';

  const size_t key_len = std::strlen(key);
  char *line = buffer;
  while (line != nullptr && *line != '\0') {
    char *next = std::strchr(line, '\n');
    if (next != nullptr) {
      *next = '\0';
      ++next;
    }
    if (std::strncmp(line, key, key_len) == 0 && line[key_len] == '=') {
      copy_string(out, out_size, line + key_len + 1);
      return true;
    }
    line = next;
  }
  return false;
}

bool mode_allows_gadget(const char *mode) {
  return std::strcmp(mode, "hybrid") == 0 || std::strcmp(mode, "gadget") == 0;
}

bool process_matches_target(const char *process, const char *target, const char *include_children) {
  if (process == nullptr || target == nullptr || target[0] == '\0') return false;
  const size_t target_len = std::strlen(target);
  if (std::strcmp(process, target) == 0) return true;
  return std::strcmp(include_children, "yes") == 0 &&
         std::strncmp(process, target, target_len) == 0 &&
         process[target_len] == ':';
}

bool file_exists_at(int dir_fd, const char *relative_path) {
  int fd = openat(dir_fd, relative_path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) return false;
  close(fd);
  return true;
}

class FridaToolboxInjector : public zygisk::ModuleBase {
public:
  void onLoad(zygisk::Api *api, JNIEnv *env) override {
    api_ = api;
    env_ = env;
  }

  void preAppSpecialize(zygisk::AppSpecializeArgs *args) override {
    if (args == nullptr || args->nice_name == nullptr) {
      api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
      return;
    }

    const char *process = env_->GetStringUTFChars(args->nice_name, nullptr);
    if (process == nullptr) {
      api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
      return;
    }

    int module_fd = api_->getModuleDir();
    if (module_fd < 0) {
      env_->ReleaseStringUTFChars(args->nice_name, process);
      api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
      return;
    }

    char mode[32] = "hybrid";
    char target[256] = "";
    char include_children[8] = "no";
    read_config_value(module_fd, "FRIDA_MODE", mode, sizeof(mode));
    read_config_value(module_fd, "GADGET_TARGET_PACKAGE", target, sizeof(target));
    read_config_value(module_fd, "GADGET_INCLUDE_CHILDREN", include_children, sizeof(include_children));

    const bool should_inject = mode_allows_gadget(mode) &&
                               process_matches_target(process, target, include_children);
    if (!should_inject) {
      close(module_fd);
      env_->ReleaseStringUTFChars(args->nice_name, process);
      api_->setOption(zygisk::DLCLOSE_MODULE_LIBRARY);
      return;
    }

    char module_dir[512] = "";
    if (!read_fd_path(module_fd, module_dir, sizeof(module_dir))) {
      copy_string(module_dir, sizeof(module_dir), kModuleFallback);
    }

    char relative_gadget[256];
    std::snprintf(relative_gadget, sizeof(relative_gadget), "gadget/%s/libfrida-gadget.so", kAbi);
    if (!file_exists_at(module_fd, relative_gadget)) {
      LOGW("missing gadget for abi=%s process=%s target=%s", kAbi, process, target);
      close(module_fd);
      env_->ReleaseStringUTFChars(args->nice_name, process);
      return;
    }

    should_inject_ = true;
    copy_string(process_, sizeof(process_), process);
    std::snprintf(gadget_path_, sizeof(gadget_path_), "%s/%s", kRuntimeBase, relative_gadget);

    close(module_fd);
    env_->ReleaseStringUTFChars(args->nice_name, process);
  }

  void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
    (void)args;
    if (!should_inject_) return;

    void *handle = dlopen(gadget_path_, RTLD_NOW | RTLD_GLOBAL);
    if (handle == nullptr) {
      LOGW("dlopen failed abi=%s process=%s path=%s error=%s", kAbi, process_, gadget_path_, dlerror());
    } else {
      LOGI("loaded gadget abi=%s process=%s path=%s handle=%p", kAbi, process_, gadget_path_, handle);
    }
  }

private:
  zygisk::Api *api_ = nullptr;
  JNIEnv *env_ = nullptr;
  bool should_inject_ = false;
  char process_[256] = "";
  char gadget_path_[768] = "";
};

}  // namespace

REGISTER_ZYGISK_MODULE(FridaToolboxInjector)
