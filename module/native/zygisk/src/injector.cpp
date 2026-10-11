#include <dlfcn.h>
#include <fcntl.h>
#include <jni.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>

#include <linux/memfd.h>

#include "zygisk.hpp"

#ifndef ZYGISK_QUIET
#define ZYGISK_QUIET 0
#endif

#if !ZYGISK_QUIET
#include <android/log.h>
#endif

namespace {

#ifndef ZYGISK_LOG_TAG
#define ZYGISK_LOG_TAG "FridaMagiskZygisk"
#endif
#ifndef ZYGISK_MODULE_FALLBACK
#define ZYGISK_MODULE_FALLBACK "/data/adb/modules/frida_magisk"
#endif
#ifndef ZYGISK_RUNTIME_FALLBACK
#define ZYGISK_RUNTIME_FALLBACK "/data/local/tmp/frida_magisk"
#endif
#ifndef ZYGISK_GADGET_FALLBACK
#define ZYGISK_GADGET_FALLBACK "libfrida-gadget.so"
#endif
#ifndef ZYGISK_MODULE_CLASS
#define ZYGISK_MODULE_CLASS FridaToolboxInjector
#endif

#if !ZYGISK_QUIET
constexpr char kTag[] = ZYGISK_LOG_TAG;
#endif
constexpr char kModuleFallback[] = ZYGISK_MODULE_FALLBACK;
constexpr char kRuntimeBase[] = ZYGISK_RUNTIME_FALLBACK;
constexpr char kGadgetBasename[] = ZYGISK_GADGET_FALLBACK;

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

#if ZYGISK_QUIET
// The injection logs run inside the target app process, so the app can read its
// own log buffer and learn both that it was injected and from where. Silent build
// drops the call, the tag and the liblog dependency.
#define LOGI(...) ((void)0)
#define LOGW(...) ((void)0)
#else
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, kTag, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, kTag, __VA_ARGS__)
#endif

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

// Copy the staged Gadget into an anonymous memfd and dlopen it through
// /proc/self/fd/N so the filesystem path never appears in the target
// process maps. Returns nullptr on any failure so the caller can fall
// back to a direct dlopen of the staged path.
void *load_gadget_via_memfd(const char *path, const char *name) {
  int src = open(path, O_RDONLY | O_CLOEXEC);
  if (src < 0) return nullptr;

  int mfd = static_cast<int>(syscall(SYS_memfd_create, name, MFD_CLOEXEC));
  if (mfd < 0) {
    close(src);
    return nullptr;
  }

  char buffer[65536];
  ssize_t len;
  bool ok = true;
  while ((len = read(src, buffer, sizeof(buffer))) > 0) {
    char *cursor = buffer;
    ssize_t remaining = len;
    while (remaining > 0) {
      ssize_t written = write(mfd, cursor, remaining);
      if (written <= 0) {
        ok = false;
        break;
      }
      cursor += written;
      remaining -= written;
    }
    if (!ok) break;
  }
  if (len < 0) ok = false;
  close(src);
  if (!ok || lseek(mfd, 0, SEEK_SET) < 0) {
    close(mfd);
    return nullptr;
  }

  char fd_path[64];
  std::snprintf(fd_path, sizeof(fd_path), "/proc/self/fd/%d", mfd);
  void *handle = dlopen(fd_path, RTLD_NOW | RTLD_GLOBAL);
  close(mfd);
  return handle;
}

class ZYGISK_MODULE_CLASS : public zygisk::ModuleBase {
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
    char runtime_base[512] = "";
    char gadget_basename[128] = "";
    read_config_value(module_fd, "FRIDA_MODE", mode, sizeof(mode));
    read_config_value(module_fd, "GADGET_TARGET_PACKAGE", target, sizeof(target));
    read_config_value(module_fd, "GADGET_INCLUDE_CHILDREN", include_children, sizeof(include_children));
    read_config_value(module_fd, "FRIDA_RUNTIME_DIR", runtime_base, sizeof(runtime_base));
    read_config_value(module_fd, "GADGET_BASENAME", gadget_basename, sizeof(gadget_basename));
    if (runtime_base[0] == '\0') copy_string(runtime_base, sizeof(runtime_base), kRuntimeBase);
    if (gadget_basename[0] == '\0') copy_string(gadget_basename, sizeof(gadget_basename), kGadgetBasename);

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
    std::snprintf(relative_gadget, sizeof(relative_gadget), "gadget/%s/%s", kAbi, gadget_basename);
    if (!file_exists_at(module_fd, relative_gadget)) {
      LOGW("missing payload for abi=%s process=%s target=%s", kAbi, process, target);
      close(module_fd);
      env_->ReleaseStringUTFChars(args->nice_name, process);
      return;
    }

    should_inject_ = true;
    copy_string(process_, sizeof(process_), process);
    copy_string(gadget_name_, sizeof(gadget_name_), gadget_basename);
    std::snprintf(gadget_path_, sizeof(gadget_path_), "%s/%s", runtime_base, relative_gadget);

    close(module_fd);
    env_->ReleaseStringUTFChars(args->nice_name, process);
  }

  void postAppSpecialize(const zygisk::AppSpecializeArgs *args) override {
    (void)args;
    if (!should_inject_) return;

    // memfd first so the staged path stays out of the app's own /proc maps;
    // fall back to the staged path on kernels or SELinux policies where the
    // memfd path is not usable.
    void *handle = load_gadget_via_memfd(gadget_path_, gadget_name_);
    if (handle == nullptr) {
      handle = dlopen(gadget_path_, RTLD_NOW | RTLD_GLOBAL);
    }
#if ZYGISK_QUIET
    (void)handle;
#else
    if (handle == nullptr) {
      LOGW("dlopen failed abi=%s process=%s path=%s error=%s", kAbi, process_, gadget_path_, dlerror());
    } else {
      LOGI("loaded payload abi=%s process=%s path=%s handle=%p", kAbi, process_, gadget_path_, handle);
    }
#endif
  }

private:
  zygisk::Api *api_ = nullptr;
  JNIEnv *env_ = nullptr;
  bool should_inject_ = false;
  char process_[256] = "";
  char gadget_path_[768] = "";
  char gadget_name_[128] = "";
};

}  // namespace

REGISTER_ZYGISK_MODULE(ZYGISK_MODULE_CLASS)
