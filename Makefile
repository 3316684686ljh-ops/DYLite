#
#  DYLite —— 抖音 UI 增强插件（精简版）
#  功能：评论区玻璃 / 分享面板玻璃 / 视频全屏 / 移除去汽水听 / 移除关注按钮
#

TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

# 目标进程：抖音主程序
INSTALL_TARGET_PROCESSES = Aweme

# 从 control 文件读取版本号
DK_VERSION := $(shell awk -F': *' '$$1 == "Version" { print $$2; exit }' control)

# 包方案：rootful / rootless / roothide
DYLITE_PACKAGE_SCHEME ?= $(if $(THEOS_PACKAGE_SCHEME),$(THEOS_PACKAGE_SCHEME),rootful)

ifeq ($(strip $(DK_VERSION)),)
$(error Missing Version in control)
endif

ifeq ($(DYLITE_PACKAGE_SCHEME),rootful)
unexport THEOS_PACKAGE_SCHEME
DYLITE_PACKAGE_SUFFIX = arm-rootful
else ifeq ($(DYLITE_PACKAGE_SCHEME),rootless)
export THEOS_PACKAGE_SCHEME = rootless
DYLITE_PACKAGE_SUFFIX = arm64-rootless
else ifeq ($(DYLITE_PACKAGE_SCHEME),roothide)
export THEOS_PACKAGE_SCHEME = roothide
DYLITE_PACKAGE_SUFFIX = arm64e-roothide
else
$(error Unsupported DYLITE_PACKAGE_SCHEME: $(DYLITE_PACKAGE_SCHEME))
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DYLite

# 自动收集所有源文件
DYLite_FILES = $(shell find src -type f \( -name '*.m' -o -name '*.mm' -o -name '*.x' -o -name '*.xm' -o -name '*.c' \) | sort)
DYLite_INCLUDE_DIRS = $(shell find src -type d | sort)

# 编译参数：开启 ARC，添加头文件路径，注入版本号
DYLite_CFLAGS = -fobjc-arc -w $(addprefix -I,$(DYLite_INCLUDE_DIRS)) -DDK_VERSION=@\"$(DK_VERSION)\"

# 依赖的系统框架
DYLite_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

# 清理命令
clean::
	@rm -rf .theos packages

# 分别打包三种方案
package-rootful::
	@rm -rf .theos
	@$(MAKE) all package DYLITE_PACKAGE_SCHEME=rootful FINALPACKAGE=1

package-rootless::
	@rm -rf .theos
	@$(MAKE) all package DYLITE_PACKAGE_SCHEME=rootless FINALPACKAGE=1

package-roothide::
	@if [ -d "$(THEOS_VENDOR_MODULE_PATH)/roothide" ] || [ -d "$(THEOS_MODULE_PATH)/roothide" ]; then \
		rm -rf .theos; \
		$(MAKE) all package DYLITE_PACKAGE_SCHEME=roothide FINALPACKAGE=1; \
	else \
		echo "warning: roothide Theos package scheme not found; skipped roothide package."; \
	fi

# 一键打包所有方案
all-packages::
	@rm -rf packages
	@mkdir -p packages
	@$(MAKE) package-rootful FINALPACKAGE=1
	@$(MAKE) package-rootless FINALPACKAGE=1
	@$(MAKE) package-roothide FINALPACKAGE=1

after-package::
	@mkdir -p packages
	@DEB=$$(cat .theos/last_package 2>/dev/null || true); \
	 OUT="packages/DYLite_$(DK_VERSION)_$(DYLITE_PACKAGE_SUFFIX).deb"; \
	 if [ -n "$$DEB" ] && [ -f "$$DEB" ]; then mv -f "$$DEB" "$$OUT"; fi
	@echo "==> 成品: packages/DYLite_$(DK_VERSION)_$(DYLITE_PACKAGE_SUFFIX).deb"
