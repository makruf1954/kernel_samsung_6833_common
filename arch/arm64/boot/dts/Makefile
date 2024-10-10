# SPDX-License-Identifier: GPL-2.0
dts-dirs += mediatek

subdir-y          := $(dts-dirs)

always-y  := $(DTB_LIST)

targets += dtbs
dtbs: $(addprefix $(obj)/, $(DTB_LIST))

clean-files       := mediatek/*.dtb *.dtb*
