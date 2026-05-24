import QtQuick
import qs.Common
import qs.Modules.Plugins
import qs.Widgets

PluginSettings {
    id: root
    pluginId: "mpvpaper-widget"

    StyledText {
        width: parent.width
        text: I18n.tr("Video Wallpaper Settings", "mpvpaper")
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: I18n.tr("A taskbar control panel to browse and switch wallpapers. Requires MpvPaper Plugin to be installed.", "mpvpaper")
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }
}
