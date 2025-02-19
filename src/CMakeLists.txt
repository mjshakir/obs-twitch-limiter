# Use existing OBS Plugin Template configurations
include(helpers)

# Set C and C++ standards globally
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Add custom plugin source files
target_sources(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
    plugin-main.c
    betting_limit/TwitchLimiterWrapper.c # C wrapper (compiled as C)
    betting_limit/TwitchLimiterWrapper.cpp # Complementary C++ wrapper (compiled as C++)
    betting_limit/TwitchLimiter.cpp
    betting_limit/eventsub.cpp
)

# Force correct language for wrapper files
set_source_files_properties(betting_limit/TwitchLimiterWrapper.c PROPERTIES LANGUAGE C)
set_source_files_properties(betting_limit/TwitchLimiterWrapper.cpp PROPERTIES LANGUAGE CXX)

# Include our plugin directory
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/betting_limit)

# Find and configure dependencies
if(WIN32)
  # On Windows use the CONFIG mode targets (provided by OBS‑deps / vcpkg)
  find_package(Boost REQUIRED COMPONENTS json system CONFIG)
  find_package(RapidJSON CONFIG REQUIRED)
else()
  find_package(Boost REQUIRED json system)
  find_package(RapidJSON REQUIRED)
endif()

find_package(libobs REQUIRED)
find_package(obs-frontend-api REQUIRED)

# Add include directories from dependencies
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

# Link the required libraries
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::libobs Boost::json Boost::system rapidjson)

# Add packaging for Windows .zip release if(WIN32) install( TARGETS
# ${CMAKE_PROJECT_NAME} RUNTIME DESTINATION "obs-plugins/64bit" LIBRARY
# DESTINATION "obs-plugins/64bit" ARCHIVE DESTINATION "obs-plugins/64bit")

# install( DIRECTORY "${CMAKE_SOURCE_DIR}/data/" DESTINATION "obs-plugins/64bit"
# FILES_MATCHING PATTERN "*")

# set(CPACK_GENERATOR "ZIP") set(CPACK_PACKAGE_NAME "${CMAKE_PROJECT_NAME}")
# set(CPACK_PACKAGE_VERSION "1.0.0") set(CPACK_PACKAGE_FILE_NAME
# "${CMAKE_PROJECT_NAME}-Windows-x64") include(CPack) endif()
