cmake_minimum_required(VERSION 3.28...3.30)

# Skip dependency resolution on Windows
if(WIN32)
  option(SKIP_DEPENDENCY_RESOLUTION "Skip the automatic dependency resolution" ON)
  if(SKIP_DEPENDENCY_RESOLUTION)
    set(BUILD_OBS OFF CACHE BOOL "Skip building OBS" FORCE)
    set(OBS_WEBRTC_ENABLED OFF CACHE BOOL "Disable WebRTC" FORCE)
  endif()
endif()

include("${CMAKE_CURRENT_SOURCE_DIR}/cmake/common/bootstrap.cmake" NO_POLICY_SCOPE)

project(${_name} VERSION ${_version})

option(ENABLE_FRONTEND_API "Use obs-frontend-api for UI functionality" ON)
option(ENABLE_QT "Use Qt functionality" ON)

include(compilerconfig)
include(defaults)
include(helpers)

# Create the plugin module
add_library(${CMAKE_PROJECT_NAME} MODULE)

if(WIN32)
  set(libobs_DIR ${CMAKE_SOURCE_DIR}/.deps/cmake)
  find_package(libobs REQUIRED CONFIG)
  find_package(obs-frontend-api REQUIRED CONFIG)
  find_package(w32-pthreads REQUIRED CONFIG)
  find_package(Boost REQUIRED COMPONENTS json system CONFIG)
  find_package(RapidJSON CONFIG REQUIRED)
else()
  # For macOS and Linux
  find_package(libobs REQUIRED)
  find_package(obs-frontend-api REQUIRED)
  find_package(Boost REQUIRED json system)
  find_package(RapidJSON REQUIRED)
endif()

# Link required libraries
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::libobs OBS::obs-frontend-api)

if(WIN32)
  target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::w32-pthreads)
endif()

# Include betting_limit sources
add_subdirectory(src)

# Additional Qt configuration if enabled
if(ENABLE_QT)
  find_package(Qt6 COMPONENTS Widgets Core)
  target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE Qt6::Core Qt6::Widgets)
  target_compile_options(
    ${CMAKE_PROJECT_NAME}
    PRIVATE $<$<C_COMPILER_ID:Clang,AppleClang>:-Wno-quoted-include-in-framework-header -Wno-comma>
  )
  set_target_properties(
    ${CMAKE_PROJECT_NAME}
    PROPERTIES AUTOMOC ON AUTOUIC ON AUTORCC ON
  )
endif()

# Add the main plugin source
target_sources(${CMAKE_PROJECT_NAME} PRIVATE src/plugin-main.c)

# Set the output name of the plugin
set_target_properties_plugin(${CMAKE_PROJECT_NAME} PROPERTIES OUTPUT_NAME ${_name})
