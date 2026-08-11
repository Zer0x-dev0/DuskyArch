import QtQuick 2.15

// Bottom-left power controls: shutdown / restart / suspend.

Item {
    id: root

    width: childrenRect.width
    height: childrenRect.height

    property color accentColor: "#9dcbfb"
    property color textColor: "#e8f2ff"
    property color bgColor: Qt.rgba(16 / 255, 20 / 255, 24 / 255, 0.55)
    property string fontFamily: "JetBrainsMono Nerd Font"

    component PowerButton: Rectangle {
        id: btn

        width: 96
        height: 64
        radius: 16
        color: root.bgColor
        border.color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1

        property string icon: ""
        property string label: ""
        property bool enabled: true
        signal clicked()

        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            id: iconText
            anchors.top: parent.top
            anchors.topMargin: 7
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.icon
            font.family: root.fontFamily
            font.pixelSize: 22
            color: btn.enabled ? root.textColor : Qt.rgba(1, 1, 1, 0.3)
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            text: btn.label
            font.family: root.fontFamily
            font.pixelSize: 10
            color: root.textColor
            opacity: 0.75
        }

        MouseArea {
            anchors.fill: parent
            enabled: btn.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
            onEntered: btn.color = Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22)
            onExited: btn.color = root.bgColor
        }
    }

    Row {
        spacing: 12

        PowerButton {
            icon: "\uf011" // nf-fa-power_off
            label: "Power"
            onClicked: sddm.powerOff()
        }

        PowerButton {
            icon: "\uf021" // nf-fa-refresh
            label: "Restart"
            onClicked: sddm.reboot()
        }

        PowerButton {
            icon: "\uf186" // nf-fa-moon_o
            label: "Suspend"
            enabled: sddm.canSuspend
            onClicked: sddm.suspend()
        }
    }
}
