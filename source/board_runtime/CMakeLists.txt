cmake_minimum_required(VERSION 3.16)
project(Yolov8PLinIOSerial LANGUAGES C CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(FPAI_DEPS_DIR "" CACHE PATH "Installed vendor deps: thirdparty headers/libraries")
if(NOT EXISTS "${FPAI_DEPS_DIR}/thirdparty/include")
    message(FATAL_ERROR "Set FPAI_DEPS_DIR to the existing vendor deps directory")
endif()
add_compile_definitions(USE_ZG330_BACKEND)
find_package(Icraft-BuyiBackend REQUIRED)
find_package(Icraft-HostBackend REQUIRED)
find_package(icraft-zg330backend REQUIRED)
find_package(Threads REQUIRED)
add_executable(yolov8_qwen_eth src/yolov8_plin_eth.cpp)
target_include_directories(yolov8_qwen_eth PRIVATE
    include ../vendor/modelzoo_utils/include
    ${FPAI_DEPS_DIR}/thirdparty/include
    ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(yolov8_qwen_eth PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
# Preserve the original example's link order. With SDK libraries first,
# the board executable failed image decoding; the vendor order passes.
target_link_libraries(yolov8_qwen_eth PRIVATE
    avformat avdevice avfilter avcodec avutil swscale swresample
    opencv_imgcodecs opencv_imgproc opencv_core tegra_hal libjpeg-turbo ittnotify libpng libwebp libtiff libopenjp2
    IlmImf-2_3_s Iex-2_3_s Half-2_3_s IexMath-2_3_s IlmImfUtil-2_3_s IlmThread-2_3_s Imath-2_3_s
    fmt pthread dl zlib yaml-cpp ssl crypto atomic
    Icraft::HostBackend Icraft::BuyiBackend Icraft::ZG330Backend
    Threads::Threads stdc++fs)

add_library(roi_gate_driver STATIC ../vendor/roi_gate/driver/mxfp8_roi_gate.c)
target_include_directories(roi_gate_driver PUBLIC ../vendor/roi_gate/driver)
target_link_libraries(roi_gate_driver PUBLIC m)
target_link_libraries(yolov8_qwen_eth PRIVATE roi_gate_driver)
add_executable(yolov8_qwen_eval src/yolov8_qwen_eval.cpp)
target_include_directories(yolov8_qwen_eval PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
get_target_property(qwen_link_libraries yolov8_qwen_eth LINK_LIBRARIES)
target_link_directories(yolov8_qwen_eval PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(yolov8_qwen_eval PRIVATE ${qwen_link_libraries})

add_library(dfl_packet STATIC ../vendor/dfl/host/dfl_decode_v1.c)
target_include_directories(dfl_packet PUBLIC ../vendor/dfl/include)
target_link_libraries(dfl_packet PUBLIC m)
target_link_libraries(yolov8_qwen_eth PRIVATE dfl_packet)
target_link_libraries(yolov8_qwen_eval PRIVATE dfl_packet)

add_executable(roi_crop_selftest src/roi_crop_selftest.cpp)
target_include_directories(roi_crop_selftest PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(roi_crop_selftest PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(roi_crop_selftest PRIVATE ${qwen_link_libraries})

add_executable(ethernet_video_probe src/ethernet_video_probe.cpp)
target_include_directories(ethernet_video_probe PRIVATE include)
target_link_libraries(ethernet_video_probe PRIVATE Threads::Threads)

add_executable(an5641_pipeline_probe src/an5641_pipeline_probe.cpp)
target_compile_definitions(an5641_pipeline_probe PRIVATE FMQL_PROFILE)
target_include_directories(an5641_pipeline_probe PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(an5641_pipeline_probe PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(an5641_pipeline_probe PRIVATE ${qwen_link_libraries} dfl_packet)

add_executable(an5641_eth_isolation src/an5641_eth_isolation.cpp)
target_compile_definitions(an5641_eth_isolation PRIVATE FMQL_PROFILE)
target_include_directories(an5641_eth_isolation PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(an5641_eth_isolation PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(an5641_eth_isolation PRIVATE ${qwen_link_libraries} dfl_packet)

add_executable(an5641_yolov8_eth src/yolov8_plin_eth.cpp)
target_compile_definitions(an5641_yolov8_eth PRIVATE FMQL_PROFILE)
target_include_directories(an5641_yolov8_eth PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(an5641_yolov8_eth PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(an5641_yolov8_eth PRIVATE ${qwen_link_libraries} dfl_packet)

add_executable(an5641_yolov8_hdmi src/yolov8_plin_hdmi.cpp)
target_compile_definitions(an5641_yolov8_hdmi PRIVATE FMQL_PROFILE)
target_include_directories(an5641_yolov8_hdmi PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(an5641_yolov8_hdmi PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(an5641_yolov8_hdmi PRIVATE ${qwen_link_libraries} dfl_packet)

# Independent transport candidate; keep the previously measured runtime intact.
add_executable(an5641_eth_lowdelay src/yolov8_plin_eth.cpp)
target_compile_definitions(an5641_eth_lowdelay PRIVATE FMQL_PROFILE FMQL_ETH_REPEAT_HEADERS)
target_include_directories(an5641_eth_lowdelay PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(an5641_eth_lowdelay PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(an5641_eth_lowdelay PRIVATE ${qwen_link_libraries} dfl_packet)

add_executable(an5641_eth_ready src/yolov8_plin_eth.cpp)
target_compile_definitions(an5641_eth_ready PRIVATE FMQL_PROFILE FMQL_ETH_PRIME)
target_include_directories(an5641_eth_ready PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(an5641_eth_ready PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(an5641_eth_ready PRIVATE ${qwen_link_libraries} dfl_packet)

# Independent full-feature HDMI target; network target retained for opt-in recording.
add_executable(yolo_qwen_esp32_hdmi src/yolov8_plin_hdmi_full.cpp)
target_compile_definitions(yolo_qwen_esp32_hdmi PRIVATE FMQL_PROFILE)
target_include_directories(yolo_qwen_esp32_hdmi PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(yolo_qwen_esp32_hdmi PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(yolo_qwen_esp32_hdmi PRIVATE ${qwen_link_libraries} dfl_packet)

add_executable(hdmi_replay_probe src/hdmi_replay_probe.cpp)
target_compile_definitions(hdmi_replay_probe PRIVATE FMQL_PROFILE)
target_include_directories(hdmi_replay_probe PRIVATE include ../vendor/modelzoo_utils/include ${FPAI_DEPS_DIR}/thirdparty/include ${FPAI_DEPS_DIR}/thirdparty/include/Eigen-3.4.0)
target_link_directories(hdmi_replay_probe PRIVATE ${FPAI_DEPS_DIR}/thirdparty/a)
target_link_libraries(hdmi_replay_probe PRIVATE ${qwen_link_libraries} dfl_packet)
