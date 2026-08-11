import QtQuick 2.15
import SddmComponents 2.0

// Translucent login card: user, password, sign-in button.

Rectangle {
    id: root

    width: 400
    height: 372
    radius: 24
    color: Qt.rgba(16 / 255, 20 / 255, 24 / 255, 0.45)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    property color accentColor: "#9dcbfb"
    property color textColor: "#e8f2ff"
    property color mutedColor: "#9fb4cc"
    property color inputBg: Qt.rgba(16 / 255, 20 / 255, 24 / 255, 0.6)
    property color inputBorder: Qt.rgba(140 / 255, 145 / 255, 153 / 255, 0.35)
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int sessionIndex: 0

    property alias userField: userEntry
    property alias passwordField: pwEntry

    Column {
        anchors.centerIn: parent
        width: parent.width - 56
        spacing: 13

        Text {
            text: "Welcome back"
            font.family: root.fontFamily
            font.pixelSize: 26
            font.weight: Font.Bold
            color: root.textColor
        }

        Text {
            text: sddm.hostName
            font.family: root.fontFamily
            font.pixelSize: 13
            color: root.accentColor
            topPadding: -6
        }

        TextBox {
            id: userEntry

            width: parent.width
            height: 46
            radius: 12
            color: root.inputBg
            borderColor: root.inputBorder
            focusColor: root.accentColor
            hoverColor: Qt.lighter(root.accentColor)
            textColor: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 15
            text: userModel.lastUser

            KeyNavigation.tab: pwEntry
        }

        PasswordBox {
            id: pwEntry

            width: parent.width
            height: 46
            radius: 12
            color: root.inputBg
            borderColor: root.inputBorder
            focusColor: root.accentColor
            hoverColor: Qt.lighter(root.accentColor)
            textColor: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 15

            KeyNavigation.backtab: userEntry
            KeyNavigation.tab: loginButton

            Keys.onPressed: {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.attemptLogin()
                    event.accepted = true
                }
            }
        }

        Rectangle {
            id: loginButton

            width: parent.width
            height: 46
            radius: 12
            color: root.accentColor

            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "Sign in  \uf090" // nf-fa-sign_in
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.Bold
                color: "#0a0d10"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.attemptLogin()
                onEntered: loginButton.color = Qt.lighter(root.accentColor, 1.1)
                onExited: loginButton.color = root.accentColor
            }
        }

        Text {
            id: errorText

            visible: false
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font.family: root.fontFamily
            font.pixelSize: 12
            color: "#ff7b9c"
            text: ""
        }
    }

    function attemptLogin() {
        if (userEntry.text.length === 0 || pwEntry.text.length === 0) {
            errorText.text = "Please enter your password"
            errorText.visible = true
            return
        }
        errorText.visible = false
        sddm.login(userEntry.text, pwEntry.text, root.sessionIndex)
    }

    Connections {
        target: sddm
        onLoginFailed: {
            errorText.text = "Login failed"
            errorText.visible = true
            pwEntry.text = ""
        }
        onInformationMessage: {
            errorText.text = message
            errorText.visible = true
        }
    }
}
