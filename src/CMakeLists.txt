# Use existing OBS Plugin Template configurations
include(helpers)

# Set C and C++ standards globally
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 17) # Ensure C files are compiled with C17
set(CMAKE_C_STANDARD_REQUIRED ON)

# Add custom plugin source files
target_sources(
  ${CMAKE_PROJECT_NAME}
  PRIVATE
    betting_limit/TwitchLimiterWrapper.c
    betting_limit/TwitchLimiterWrapper.cpp
    betting_limit/TwitchLimiter.cpp
    betting_limit/eventsub.cpp
)

# Ensure `TwitchLimiterWrapper.c` is compiled as C and `TwitchLimiterWrapper.cpp` as C++
set_source_files_properties(betting_limit/TwitchLimiterWrapper.c PROPERTIES LANGUAGE C)
set_source_files_properties(betting_limit/TwitchLimiterWrapper.cpp PROPERTIES LANGUAGE CXX)

# Include plugin directories
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/betting_limit)

# Link dependencies
target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE OBS::libobs Boost::json Boost::system ${OBS_FRONTEND_API_LIBRARIES})
