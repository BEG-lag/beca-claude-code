# Compila en la caché local: las carpetas sincronizadas, como iCloud, agregan atributos que rompen la firma del bundle.
BUILD := $(HOME)/Library/Caches/AxoBuild
BUNDLE := $(BUILD)/BeCa.app
INSTALL_APP := $(HOME)/Applications/BeCa.app
AXO_HOME := $(HOME)/.axo

.PHONY: build install

build:
	rm -rf "$(BUNDLE)"
	mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	swiftc -O -framework AppKit -o "$(BUNDLE)/Contents/MacOS/BeCa" app/main.swift
	cp app/Info.plist "$(BUNDLE)/Contents/Info.plist"
	cp -R app/clips "$(BUNDLE)/Contents/Resources/clips"
	cp -R app/sounds "$(BUNDLE)/Contents/Resources/sounds"
	clang -O2 -o "$(BUILD)/axo-state" hooks/axo-state.c
	xattr -cr "$(BUNDLE)"
	codesign --force --sign - "$(BUNDLE)"

install: build
	-pkill -x Axo
	-pkill -x BeCa
	rm -rf "$(HOME)/Applications/Axo.app"
	mkdir -p "$(HOME)/Applications" "$(AXO_HOME)/status"
	rm -rf "$(INSTALL_APP)"
	cp -R "$(BUNDLE)" "$(INSTALL_APP)"
	install -m 755 "$(BUILD)/axo-state" "$(AXO_HOME)/axo-state"
	install -m 755 bin/axo "$(AXO_HOME)/axo"
	ln -sf axo "$(AXO_HOME)/beca"
	install -m 644 hooks/hooks.json "$(AXO_HOME)/hooks.json"
	@echo "Instalado. Abre con: ~/.axo/beca abrir"
