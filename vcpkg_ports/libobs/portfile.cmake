# This portfile doesn't actually build libobs—it simply “installs” the already‐built files.
if(NOT DEFINED ENV{LIBOBS_INSTALL_DIR})
    message(FATAL_ERROR "Please set the LIBOBS_INSTALL_DIR environment variable to the libobs install directory.")
endif()
# Convert LIBOBS_INSTALL_DIR to a CMake path:
file(TO_CMAKE_PATH "$ENV{LIBOBS_INSTALL_DIR}" LIBOBS_ROOT)

# Install the configuration files (and headers, if needed)
# Adjust the installation commands if your libobs install has a different layout.
file(INSTALL ${LIBOBS_ROOT} DESTINATION ${CURRENT_PACKAGES_DIR}/lib/cmake/libobs)
