ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeepBlockNetwork
DeepBlockNetwork_FILES = Tweak.xm fishhook.c
DeepBlockNetwork_CFLAGS = -fobjc-arc -Wno-error
DeepBlockNetwork_LDFLAGS = -ldl

include $(THEOS_MAKE_PATH)/tweak.mk
