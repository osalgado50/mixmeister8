cmake_minimum_required(VERSION 3.20)
project(mmstudio_next_engine LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

add_library(mmn
  src/audio/audio.cpp
  src/dsp/dsp.cpp
  src/analysis/rhythm.cpp
  src/analysis/key.cpp
  src/mix/stretch.cpp
  src/mix/mix.cpp
  src/formats/mxm.cpp
  src/formats/mmp.cpp)
target_include_directories(mmn PUBLIC include PRIVATE third_party/minimp3)
if(APPLE)
  # AAC/M4A y demás formatos del sistema vía Core Audio
  target_link_libraries(mmn PRIVATE "-framework AudioToolbox" "-framework CoreFoundation" "-framework Accelerate")
endif()
if(MSVC)
  target_compile_options(mmn PRIVATE /W4)
else()
  target_compile_options(mmn PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wno-sign-conversion)
  # minimp3 es de terceros: sin avisos de conversión en su cabecera
  set_source_files_properties(src/audio/audio.cpp PROPERTIES COMPILE_OPTIONS "-Wno-conversion;-Wno-pedantic")
endif()

add_executable(mmn_cli apps/mmn.cpp)
set_target_properties(mmn_cli PROPERTIES OUTPUT_NAME mmn)
target_link_libraries(mmn_cli PRIVATE mmn)

enable_testing()
add_executable(mmn_tests tests/test_main.cpp tests/test_dsp_audio.cpp tests/test_rhythm.cpp tests/test_key.cpp tests/test_stretch.cpp tests/test_mix.cpp tests/test_mmp.cpp)
target_include_directories(mmn_tests PRIVATE third_party/doctest)
target_link_libraries(mmn_tests PRIVATE mmn)
add_test(NAME mmn_tests COMMAND mmn_tests)

# API en C para la app (y la comprobación de ida y vuelta por JSON contra listas reales)
add_library(mmn_c capi/mmn_c.cpp capi/mmn_fx.cpp capi/mmn_loud.cpp)
target_include_directories(mmn_c PUBLIC capi/include)
target_link_libraries(mmn_c PUBLIC mmn)
add_executable(mmn_capi_check tools/capi_check.cpp)
target_link_libraries(mmn_capi_check PRIVATE mmn_c)
