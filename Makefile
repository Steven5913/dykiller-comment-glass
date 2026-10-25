export THEOS         ?= $(HOME)/theos
TARGET               = iphone:clang:15.0:14.0
ARCHS                = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ForceDYKillerPrefs

ForceDYKillerPrefs_FILES = Tweak.xm
ForceDYKillerPrefs_CFLAGS = -fobjc-arc
ForceDYKillerPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
