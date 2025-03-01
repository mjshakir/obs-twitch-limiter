# Use existing OBS Plugin Template configurations
include(helpers)

# Set C and C++ standards globally
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 17) # Ensure C files are compiled with C17
set(CMAKE_C_STANDARD_REQUIRED ON)

option(USE_FALLBACK_LIBOBS "Use prebuilt/fallback libobs instead of adding OBS Studio subdirectory" OFF)

# Add custom plugin source files
target_sources(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
    betting_limit/TwitchLimiterWrapper.c # Compiled as C
    betting_limit/TwitchLimiterWrapper.cpp # Compiled as C++
    betting_limit/TwitchLimiter.cpp
    betting_limit/eventsub.cpp
)

# Ensure `TwitchLimiterWrapper.c` is compiled as C and `TwitchLimiterWrapper.cpp` as C++
set_source_files_properties(betting_limit/TwitchLimiterWrapper.c PROPERTIES LANGUAGE C)
set_source_files_properties(betting_limit/TwitchLimiterWrapper.cpp PROPERTIES LANGUAGE CXX)

# Include plugin directories
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/betting_limit)

# Link required libraries
# Find Boost components
# find_package(Boost REQUIRED json system)

# Find RapidJSON
# find_package(RapidJSON REQUIRED)

# Find and configure dependencies
if(WIN32)
  set(libobs_DIR ${CMAKE_SOURCE_DIR}/.deps/cmake)
  find_package(libobs REQUIRED CONFIG)
  find_package(obs-frontend-api REQUIRED CONFIG)
  find_package(Boost REQUIRED COMPONENTS json system CONFIG)
  find_package(RapidJSON CONFIG REQUIRED)
else()
  find_package(libobs REQUIRED)
  find_package(obs-frontend-api REQUIRED)
  find_package(Boost REQUIRED json system)
  find_package(RapidJSON REQUIRED)
endif()

# Include directories
if(Boost_FOUND)
  include_directories(${Boost_INCLUDE_DIRS})
  link_directories(${Boost_LIBRARY_DIRS})
endif()

if(RapidJSON_FOUND)
  include_directories(${RapidJSON_INCLUDE_DIRS})
endif()

if(libobs_FOUND)
  include_directories(${libobs_INCLUDE_DIRS})
endif()

if(obs-frontend-api_FOUND)
  include_directories(${obs-frontend-api_INCLUDE_DIRS})
endif()

# Link dependencies to the plugin
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::libobs Boost::json Boost::system ${OBS_FRONTEND_API_LIBRARIES})

# Add packaging for Windows .zip release if(WIN32) install( TARGETS
# ${CMAKE_PROJECT_NAME} RUNTIME DESTINATION "obs-plugins/64bit" LIBRARY
# DESTINATION "obs-plugins/64bit" ARCHIVE DESTINATION "obs-plugins/64bit")

# install( DIRECTORY "${CMAKE_SOURCE_DIR}/data/" DESTINATION "obs-plugins/64bit"
# FILES_MATCHING PATTERN "*")

# set(CPACK_GENERATOR "ZIP") set(CPACK_PACKAGE_NAME "${CMAKE_PROJECT_NAME}")
# set(CPACK_PACKAGE_VERSION "1.0.0") set(CPACK_PACKAGE_FILE_NAME
# "${CMAKE_PROJECT_NAME}-Windows-x64") include(CPack) endif()
