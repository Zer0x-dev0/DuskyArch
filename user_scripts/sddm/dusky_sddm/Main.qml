import QtQuick 2.15
import SddmComponents 2.0

Rectangle {
    id: root

    width: 640
    height: 480
    color: "#0a0d10"

    function cfg(key, fallback) {
        var v = config[key]
        return (v === undefined || v === "") ? fallback : v
    }

    property string fontFamily: cfg("fontFamily", "JetBrainsMono Nerd Font")
    property color accentColor: cfg("accentColor", "#9dcbfb")
    property color textColor: cfg("textColor", "#e8f2ff")
    property color mutedColor: cfg("mutedColor", "#9fb4cc")

    // Sharp HD wallpaper
    Image {
        id: background

        anchors.fill: parent
        source: config.background
        fillMode: Image.PreserveAspectCrop
        onStatusChanged: {
            if (status == Image.Error && source != "") {
                source = ""
            }
        }
    }

    // Vibrant blur-behind layer
    BlurLayer {
        id: blurLayer

        anchors.fill: parent
        source: background
        texelSize: Qt.vector2d(1.0 / root.width, 1.0 / root.height)
        blurRadius: parseFloat(cfg("blurRadius", "18.0"))
        saturation: parseFloat(cfg("saturation", "1.28"))
        opacity: parseFloat(cfg("blurOpacity", "0.85"))
    }

    // Subtle readability gradient
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(10 / 255, 13 / 255, 16 / 255, 0.35) }
            GradientStop { position: 0.5; color: "transparent" }
            GradientStop { position: 1.0; color: Qt.rgba(10 / 255, 13 / 255, 16 / 255, 0.5) }
        }
    }

    // Top-right system status
    StatusBar {
        anchors.top: parent.top
        anchors.right: parent.right
        textColor: root.textColor
        mutedColor: root.mutedColor
        fontFamily: root.fontFamily
    }

    // Centered translucent login card
    LoginCard {
        id: loginCard

        anchors.centerIn: parent
        accentColor: root.accentColor
        textColor: root.textColor
        mutedColor: root.mutedColor
        fontFamily: root.fontFamily
        sessionIndex: sessionSelector.index
    }

    // Bottom-left: session selector above power controls
    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 32
        anchors.bottomMargin: 28
        spacing: 14

        Rectangle {
            width: 220
            height: 42
            radius: 12
            color: Qt.rgba(16 / 255, 20 / 255, 24 / 255, 0.55)
            border.color: Qt.rgba(1, 1, 1, 0.14)
            border.width: 1

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 10

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\uf013" // nf-fa-gear
                    font.family: root.fontFamily
                    font.pixelSize: 16
                    color: root.mutedColor
                }

                ComboBox {
                    id: sessionSelector

                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    height: parent.height

                    color: "transparent"
                    borderColor: "transparent"
                    focusColor: "transparent"
                    hoverColor: "transparent"
                    menuColor: Qt.rgba(16 / 255, 20 / 255, 24 / 255, 0.95)
                    textColor: root.textColor
                    borderWidth: 0
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    arrowColor: root.accentColor

                    model: sessionModel
                    index: sessionModel.lastIndex
                }
            }
        }

        PowerControls {
            accentColor: root.accentColor
            textColor: root.textColor
            fontFamily: root.fontFamily
        }
    }

    Component.onCompleted: {
        if (loginCard.userField.text === "") {
            loginCard.userField.focus = true
        } else {
            loginCard.passwordField.focus = true
        }
    }
}
