# Use existing OBS Plugin Template configurations
include(helpers)

# Set C++ standard globally
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Add custom plugin source files
target_sources(${CMAKE_PROJECT_NAME} PRIVATE
    plugin-main.c
    betting_limit/plugin.cpp
    betting_limit/eventsub.cpp
)

# Include your plugin directory
target_include_directories(${CMAKE_PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/betting_limit)

# Link required libraries
find_package(Boost REQUIRED COMPONENTS json system asio)
find_package(websocketpp REQUIRED)
find_package(RapidJSON REQUIRED)

target_link_libraries(${CMAKE_PROJECT_NAME} PRIVATE
    OBS::libobs
    Boost::json
    Boost::system
    Boost::asio
    websocketpp
    RapidJSON::RapidJSON
)

# Add packaging for Windows .zip release
if(WIN32)
    install(TARGETS ${CMAKE_PROJECT_NAME}
        RUNTIME DESTINATION "obs-plugins/64bit"
        LIBRARY DESTINATION "obs-plugins/64bit"
        ARCHIVE DESTINATION "obs-plugins/64bit"
    )

    install(DIRECTORY "${CMAKE_SOURCE_DIR}/data/"
        DESTINATION "obs-plugins/64bit"
        FILES_MATCHING PATTERN "*"
    )

    set(CPACK_GENERATOR "ZIP")
    set(CPACK_PACKAGE_NAME "${CMAKE_PROJECT_NAME}")
    set(CPACK_PACKAGE_VERSION "1.0.0")
    set(CPACK_PACKAGE_FILE_NAME "${CMAKE_PROJECT_NAME}-Windows-x64")
    include(CPack)
endif()