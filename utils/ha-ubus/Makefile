include $(TOPDIR)/rules.mk

PKG_NAME:=ha-ubus
PKG_RELEASE:=1

PKG_MAINTAINER:=Jakub Znamenáček <ZnamenacekJakub@gmail.com>
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=

include $(INCLUDE_DIR)/package.mk

define Package/ha-ubus
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Read-only ubus login for Home Assistant
  URL:=https://www.home-assistant.io/integrations/ubus
  DEPENDS:=+rpcd +rpcd-mod-file +uhttpd +uhttpd-mod-ubus
  PKGARCH:=all
endef

define Package/ha-ubus/description
  Creates a read-only rpcd login for the Home Assistant OpenWrt (ubus)
  integration. The login can only list wireless clients and read the DHCP
  configuration and leases. Run 'ha-ubus show' to print the values to enter
  in Home Assistant.
endef

Build/Compile=

define Package/ha-ubus/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) ./files/ha-ubus.sh $(1)/usr/sbin/ha-ubus
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./files/ha-ubus.json $(1)/usr/share/rpcd/acl.d/ha-ubus.json
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/ha-ubus.uci-defaults $(1)/etc/uci-defaults/90_ha-ubus
	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/ha-ubus.upgrade $(1)/lib/upgrade/keep.d/ha-ubus
endef

define Package/ha-ubus/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ "$${PKG_UPGRADE}" = "1" ] || /usr/sbin/ha-ubus show
exit 0
endef

define Package/ha-ubus/prerm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
[ "$${PKG_UPGRADE}" = "1" ] && exit 0
/usr/sbin/ha-ubus remove
exit 0
endef

$(eval $(call BuildPackage,ha-ubus))
