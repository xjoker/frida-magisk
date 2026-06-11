cmake_minimum_required(VERSION 3.22)
project(frida_magisk_zygisk LANGUAGES CXX)

add_library(frida_magisk_zygisk SHARED src/injector.cpp)

target_include_directories(frida_magisk_zygisk PRIVATE include)
target_compile_features(frida_magisk_zygisk PRIVATE cxx_std_17)
target_compile_options(frida_magisk_zygisk PRIVATE
  -Wall
  -Wextra
  -Werror
  -fvisibility=hidden
  -fno-exceptions
  -fno-rtti
)
target_link_options(frida_magisk_zygisk PRIVATE -Wl,--gc-sections)
target_link_libraries(frida_magisk_zygisk PRIVATE log dl)
