#=============================================================================
#  DYKiller Comment Liquid Glass (模糊玻璃模式) — Theos 工程
#  目标：iOS 14.0+，arm64 / arm64e（你自签侧载的是 arm64e 设备）
#  用法：在 macOS 上（或 GitHub Actions macOS runner）执行
#         make clean && make package
#  产物：.theos/obj/debug/arm64e/DYKillerCommentGlass.dylib
#=============================================================================

export THEOS         ?= $(HOME)/theos
TARGET               = iphone:clang:15.0:14.0
ARCHS                = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYKillerCommentGlass

DYKillerCommentGlass_FILES = Tweak.xm
DYKillerCommentGlass_CFLAGS = -fobjc-arc
DYKillerCommentGlass_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
