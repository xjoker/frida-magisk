cmake_minimum_required(VERSION 3.22)
project(frida_magisk_zygisk LANGUAGES CXX)

set(ZYGISK_LOG_TAG "FridaMagiskZygisk" CACHE STRING "Zygisk module log tag")
set(ZYGISK_MODULE_FALLBACK "/data/adb/modules/frida_magisk" CACHE STRING "Fallback module path")
set(ZYGISK_RUNTIME_FALLBACK "/data/local/tmp/frida_magisk" CACHE STRING "Fallback runtime path")
set(ZYGISK_GADGET_FALLBACK "libfrida-gadget.so" CACHE STRING "Fallback Gadget basename")
set(ZYGISK_MODULE_CLASS "FridaToolboxInjector" CACHE STRING "Zygisk module C++ class name")
set(ZYGISK_OUTPUT_NAME "frida_magisk_zygisk" CACHE STRING "Native library output name")
# 1 compiles the logcat output out entirely: no LOGI/LOGW call, no liblog linkage.
# postAppSpecialize runs inside the target app process, so those lines are readable
# from the app's own log buffer and confirm the injection.
set(ZYGISK_QUIET "0" CACHE STRING "Compile out Zygisk logcat output (1 = silent)")

add_library(frida_magisk_zygisk SHARED src/injector.cpp)
set_target_properties(frida_magisk_zygisk PROPERTIES OUTPUT_NAME "${ZYGISK_OUTPUT_NAME}")

target_include_directories(frida_magisk_zygisk PRIVATE include)
target_compile_features(frida_magisk_zygisk PRIVATE cxx_std_17)
target_compile_definitions(frida_magisk_zygisk PRIVATE
  ZYGISK_LOG_TAG="${ZYGISK_LOG_TAG}"
  ZYGISK_MODULE_FALLBACK="${ZYGISK_MODULE_FALLBACK}"
  ZYGISK_RUNTIME_FALLBACK="${ZYGISK_RUNTIME_FALLBACK}"
  ZYGISK_GADGET_FALLBACK="${ZYGISK_GADGET_FALLBACK}"
  ZYGISK_MODULE_CLASS=${ZYGISK_MODULE_CLASS}
  ZYGISK_QUIET=${ZYGISK_QUIET}
)
target_compile_options(frida_magisk_zygisk PRIVATE
  -Wall
  -Wextra
  -Werror
  -fvisibility=hidden
  -fno-exceptions
  -fno-rtti
)
target_link_options(frida_magisk_zygisk PRIVATE -Wl,--gc-sections)
if(ZYGISK_QUIET)
  target_link_libraries(frida_magisk_zygisk PRIVATE dl)
else()
  target_link_libraries(frida_magisk_zygisk PRIVATE log dl)
endif()
