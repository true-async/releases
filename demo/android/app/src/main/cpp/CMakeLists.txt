cmake_minimum_required(VERSION 3.22.1)
project("phpbridge")

# PHP headers are extracted from the artifact ZIP into:
#   app/src/main/cpp/include/php/
set(PHP_INCLUDE "${CMAKE_SOURCE_DIR}/include/php")

# Static libs are extracted into:
#   app/src/main/jniLibs/{abi}/
set(PHP_LIBS "${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}")

add_library(phpbridge SHARED php_bridge.c)

target_compile_definitions(phpbridge PRIVATE HAVE_CONFIG_H=1)

target_include_directories(phpbridge PRIVATE
    ${PHP_INCLUDE}
    ${PHP_INCLUDE}/main
    ${PHP_INCLUDE}/Zend
    ${PHP_INCLUDE}/TSRM
    ${PHP_INCLUDE}/ext
)

target_link_libraries(phpbridge
    -Wl,--start-group
        ${PHP_LIBS}/libphp.a
        ${PHP_LIBS}/libuv.a
        ${PHP_LIBS}/libssl.a
        ${PHP_LIBS}/libcrypto.a
        ${PHP_LIBS}/libxml2.a
        ${PHP_LIBS}/libsqlite3.a
        ${PHP_LIBS}/libcurl.a
        ${PHP_LIBS}/libz.a
    -Wl,--end-group
    android
    log
    dl
    m
    z
)
