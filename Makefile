THEOS_PACKAGE_SCHEME = rootless
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = xz
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

before-all::
	$(ECHO_NOTHING)python3 Scripts/configure_targets.py$(ECHO_END)

TWEAK_NAME = NetCapture
NetCapture_FILES = \
    Tweak/Tweak.xm \
    Tweak/Hook/NCHookRegistry.mm \
    Tweak/Hook/NCURLSessionHook.mm \
    Tweak/Core/NCCaptureManager.mm \
    Tweak/IPC/NCIPCClient.mm \
    Shared/NCProtocol.mm \
    Shared/NCModels.mm \
    Shared/NCHeaderField.mm \
    Shared/NCRuntimePaths.mm
NetCapture_CFLAGS = -fobjc-arc
NetCapture_CCFLAGS = -std=c++17
NetCapture_FRAMEWORKS = Foundation
NetCapture_LIBRARIES = substrate

TOOL_NAME = netcaptured
netcaptured_FILES = \
    Daemon/main.mm \
    Daemon/NCIPCServer.mm \
    Daemon/NCClientConnection.mm \
    Daemon/NCTransactionAssembler.mm \
    Daemon/Model/NCServerModels.mm \
    Daemon/Storage/NCDatabase.mm \
    Daemon/Storage/NCBodyWriter.mm \
    Shared/NCProtocol.mm \
    Shared/NCModels.mm \
    Shared/NCHeaderField.mm \
    Shared/NCRuntimePaths.mm
netcaptured_CFLAGS = -fobjc-arc
netcaptured_CCFLAGS = -std=c++17
netcaptured_FRAMEWORKS = Foundation
netcaptured_LIBRARIES = sqlite3
netcaptured_INSTALL_PATH = /usr/libexec

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)cp Packaging/com.netcapture.daemon.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.netcapture.daemon.plist$(ECHO_END)
