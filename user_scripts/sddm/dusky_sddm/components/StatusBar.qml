import QtQuick 2.15

// Top-right system status: wifi + battery icons, clock and date.

Item {
    id: root

    width: 340
    height: 160

    property color textColor: "#e8f2ff"
    property color mutedColor: "#9fb4cc"
    property string fontFamily: "JetBrainsMono Nerd Font"

    Column {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 36
        spacing: 4

        Row {
            anchors.right: parent.right
            spacing: 14

            Text {
                text: "\uf1eb" // nf-fa-wifi
                font.family: root.fontFamily
                font.pixelSize: 20
                color: root.mutedColor
            }

            Text {
                text: "\uf240" // nf-fa-battery_full
                font.family: root.fontFamily
                font.pixelSize: 20
                color: root.mutedColor
            }
        }

        Text {
            id: clockText
            anchors.right: parent.right
            font.family: root.fontFamily
            font.pixelSize: 44
            font.weight: Font.Bold
            color: root.textColor
            text: Qt.formatTime(new Date(), "HH:mm")
        }

        Text {
            id: dateText
            anchors.right: parent.right
            font.family: root.fontFamily
            font.pixelSize: 13
            color: root.mutedColor
            text: Qt.formatDate(new Date(), "dddd, dd MMMM")
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            clockText.text = Qt.formatTime(new Date(), "HH:mm")
            dateText.text = Qt.formatDate(new Date(), "dddd, dd MMMM")
        }
    }
}
