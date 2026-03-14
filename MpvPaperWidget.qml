import QtCore
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    pluginId: "mpvpaper-widget"

    property var monitors: Quickshell.screens.map(screen => screen.name)
    property string selectedMonitor: {
        // 优先使用当前屏幕，如果没有则使用第一个
        if (parentScreen && parentScreen.name) {
            return parentScreen.name
        }
        return monitors.length > 0 ? monitors[0] : ""
    }
    property int currentPage: 0
    property int itemsPerPage: 16  // 4x4 grid
    property int totalPages: Math.max(1, Math.ceil(getPlaylist().length / itemsPerPage))
    property int refreshTrigger: 0
    property int gridIndex: 0
    property bool enableAnimation: false
    property var thumbnailQueue: []
    property bool isGeneratingThumbnail: false

    function queueThumbnail(videoPath, callback) {
        thumbnailQueue.push({path: videoPath, callback: callback})
        if (!isGeneratingThumbnail) {
            processNextThumbnail()
        }
    }

    function processNextThumbnail() {
        if (thumbnailQueue.length === 0) {
            isGeneratingThumbnail = false
            return
        }
        
        isGeneratingThumbnail = true
        const task = thumbnailQueue.shift()
        
        // 调用底层的生成逻辑（这里利用一个隐藏的 Process 组件或者 delegate 内的组件）
        // 为了保持简单，我们还是让 delegate 自己持有逻辑，但由 queue 控制开关
        task.callback()
    }
    Connections {
        target: pluginService
        
        function onPluginDataChanged(changedPluginId) {
            if (changedPluginId === "mpvpaper") {
                console.log("=== MpvPaper Widget: Daemon data changed ===")
                root.refreshTrigger++
            }
        }
    }

    onPluginDataChanged: {
        console.log("=== MpvPaper Widget: pluginData changed ===")
        console.log("MpvPaper Widget: own pluginData:", JSON.stringify(pluginData))
        refreshTrigger++
    }

    Component.onCompleted: {
        console.log("=== MpvPaper Widget: Component completed ===")
        console.log("MpvPaper Widget: pluginId:", pluginId)
        console.log("MpvPaper Widget: pluginService:", pluginService)
        console.log("MpvPaper Widget: parentScreen:", parentScreen ? parentScreen.name : "null")
        console.log("MpvPaper Widget: own pluginData:", JSON.stringify(pluginData))
        console.log("MpvPaper Widget: monitors:", JSON.stringify(monitors))
        console.log("MpvPaper Widget: selectedMonitor:", selectedMonitor)
        
        // 尝试读取 daemon 数据
        if (pluginService) {
            const daemonPlaylists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
            const daemonVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
            console.log("MpvPaper Widget: daemon monitorPlaylists:", JSON.stringify(daemonPlaylists))
            console.log("MpvPaper Widget: daemon monitorVideos:", JSON.stringify(daemonVideos))
        }
    }

    onRefreshTriggerChanged: {
        // When data changes, update gridIndex to match current video
        const currentPath = getCurrentVideoPath()
        const playlist = getPlaylist()
        const startIndex = currentPage * itemsPerPage
        const pagePlaylist = playlist.slice(startIndex, Math.min(startIndex + itemsPerPage, playlist.length))
        const idx = pagePlaylist.indexOf(currentPath)
        if (idx !== -1) {
            gridIndex = idx
        }
    }

    function getPlaylist() {
        // 从 mpvpaper daemon 读取数据
        if (!pluginService) return []
        const playlists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
        var list = playlists[selectedMonitor]
        console.log("MpvPaper Widget: getPlaylist for", selectedMonitor, "- playlists:", JSON.stringify(playlists), "list:", list)
        return Array.isArray(list) ? list : []
    }

    function getCurrentVideoPath() {
        // 从 mpvpaper daemon 读取数据
        if (!pluginService) return ""
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
        var path = monitorVideos[selectedMonitor] || ""
        console.log("MpvPaper Widget: getCurrentVideoPath for", selectedMonitor, "- monitorVideos:", JSON.stringify(monitorVideos), "path:", path)
        return path
    }

    function setCurrentVideo(videoPath) {
        console.log("MpvPaper Widget: Switching to video:", videoPath, "on monitor:", selectedMonitor)
        
        if (!pluginService) {
            console.error("MpvPaper Widget: pluginService is null")
            return
        }
        
        // 读取 daemon 数据
        const playlists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
        var playlist = playlists[selectedMonitor]
        
        if (playlist && Array.isArray(playlist)) {
            var videoIndex = playlist.indexOf(videoPath)
            if (videoIndex !== -1) {
                const indices = pluginService.loadPluginData("mpvpaper", "playlistIndices", {})
                indices[selectedMonitor] = videoIndex
                pluginService.savePluginData("mpvpaper", "playlistIndices", indices)
            }
        }
        
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
        monitorVideos[selectedMonitor] = videoPath
        pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)
    }

    function openSystemFilePicker() {
        systemFilePickerProcess.running = true
    }

    function addToPlaylist(videoPath) {
        if (!pluginService) return
        
        // 读取 daemon 数据
        const playlists = pluginService.loadPluginData("mpvpaper", "monitorPlaylists", {})
        if (!playlists[selectedMonitor]) {
            playlists[selectedMonitor] = []
        }
        
        if (playlists[selectedMonitor].indexOf(videoPath) !== -1) {
            ToastService.showWarning("视频已存在", "该视频已在列表中")
            return
        }
        
        playlists[selectedMonitor].push(videoPath)
        pluginService.savePluginData("mpvpaper", "monitorPlaylists", playlists)
        
        const monitorVideos = pluginService.loadPluginData("mpvpaper", "monitorVideos", {})
        monitorVideos[selectedMonitor] = videoPath
        pluginService.savePluginData("mpvpaper", "monitorVideos", monitorVideos)
        
        refreshTrigger++
        ToastService.showInfo("视频已添加", videoPath.substring(videoPath.lastIndexOf('/') + 1))
    }

    Process {
        id: systemFilePickerProcess
        property string selectedFile: ""

        command: ["bash", "-c",
            `if command -v zenity >/dev/null 2>&1; then
                zenity --file-selection --title="选择视频文件" --file-filter="视频文件 | *.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v" --file-filter="所有文件 | *"
            elif command -v kdialog >/dev/null 2>&1; then
                kdialog --getopenfilename ~ "*.mp4 *.mkv *.webm *.avi *.mov *.flv *.wmv *.m4v|视频文件"
            else
                echo "ERROR: No file picker available"
                exit 1
            fi`
        ]

        stdout: SplitParser {
            onRead: (data) => {
                systemFilePickerProcess.selectedFile += data
            }
        }

        onExited: (code) => {
            const trimmedFile = selectedFile.trim()
            if (code === 0 && trimmedFile !== "") {
                addToPlaylist(trimmedFile)
            }
            selectedFile = ""
        }
    }

    horizontalBarPill: Component {
        DankIcon {
            name: "movie"
            size: root.iconSize
            color: Theme.primary
            
            Component.onCompleted: {
                console.log("=== MpvPaper Widget: horizontalBarPill created ===")
            }
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "movie"
            size: root.iconSize
            color: Theme.primary
            
            Component.onCompleted: {
                console.log("=== MpvPaper Widget: verticalBarPill created ===")
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout

            Component.onCompleted: {
                console.log("=== MpvPaper Widget: popoutContent created ===")
                console.log("MpvPaper Widget Popout: pluginData:", JSON.stringify(root.pluginData))
                console.log("MpvPaper Widget Popout: getPlaylist():", JSON.stringify(root.getPlaylist()))
            }

            headerText: "视频壁纸"
            detailsText: {
                root.refreshTrigger
                const playlist = root.getPlaylist()
                if (playlist.length === 0) return "暂无壁纸"
                if (root.totalPages > 1) {
                    return `${playlist.length} 个壁纸 • 第 ${root.currentPage + 1}/${root.totalPages} 页`
                }
                return `${playlist.length} 个壁纸`
            }
            showCloseButton: true

            Item {
                width: parent.width
                implicitHeight: root.popoutHeight - popout.headerHeight - popout.detailsHeight - Theme.spacingXL

                Column {
                    anchors.fill: parent
                    spacing: 0

                    // Monitor selector (if multiple monitors)
                    Item {
                        width: parent.width
                        height: root.monitors.length > 1 ? 60 : 0
                        visible: root.monitors.length > 1

                        Row {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingM
                            anchors.bottomMargin: Theme.spacingL
                            spacing: Theme.spacingM

                            StyledText {
                                text: "显示器"
                                font.pixelSize: Theme.fontSizeSmall
                                width: 60
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            DankDropdown {
                                width: parent.width - 60 - Theme.spacingM
                                height: parent.height - Theme.spacingM * 2
                                anchors.verticalCenter: parent.verticalCenter
                                options: root.monitors
                                currentValue: root.selectedMonitor || "无显示器"
                                compactMode: true

                                onValueChanged: (value) => {
                                    root.selectedMonitor = value
                                    root.currentPage = 0
                                    root.gridIndex = 0
                                }
                            }
                        }
                    }

                    // Video grid
                    Item {
                        width: parent.width
                        height: parent.height - (root.monitors.length > 1 ? 60 : 0) - 50

                        GridView {
                            id: videoGrid
                            anchors.centerIn: parent
                            width: parent.width - Theme.spacingS
                            height: parent.height - Theme.spacingS
                            cellWidth: width / 4
                            cellHeight: cellWidth * 9 / 16
                            clip: true
                            interactive: false
                            boundsBehavior: Flickable.StopAtBounds
                            highlightFollowsCurrentItem: true
                            highlightMoveDuration: enableAnimation ? Theme.shortDuration : 0

                            highlight: Item {
                                z: 1000
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingXS
                                    color: "transparent"
                                    border.width: 3
                                    border.color: Theme.primary
                                    radius: Theme.cornerRadius
                                }
                            }

                            model: {
                                root.refreshTrigger
                                const playlist = root.getPlaylist()
                                const startIndex = root.currentPage * root.itemsPerPage
                                const endIndex = Math.min(startIndex + root.itemsPerPage, playlist.length)
                                return playlist.slice(startIndex, endIndex)
                            }

                            onCountChanged: {
                                if (count > 0) {
                                    const clampedIndex = Math.min(root.gridIndex, count - 1)
                                    currentIndex = clampedIndex
                                }
                                Qt.callLater(() => {
                                    root.enableAnimation = true
                                })
                            }

                            Connections {
                                target: root
                                function onGridIndexChanged() {
                                    if (videoGrid.count > 0) {
                                        videoGrid.currentIndex = root.gridIndex
                                    }
                                }
                            }

                            delegate: Item {
                                width: videoGrid.cellWidth
                                height: videoGrid.cellHeight

                                property string videoPath: modelData || ""
                                property bool isSelected: {
                                    root.refreshTrigger
                                    return root.getCurrentVideoPath() === modelData
                                }

                                Rectangle {
                                    id: videoCard
                                    anchors.fill: parent
                                    anchors.margins: Theme.spacingXS
                                    color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)
                                    radius: Theme.cornerRadius
                                    clip: true

                                    Rectangle {
                                        anchors.fill: parent
                                        color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                        radius: parent.radius

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: Theme.shortDuration
                                                easing.type: Theme.standardEasing
                                            }
                                        }
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: isSelected ? 3 : 0
                                        border.color: Theme.primary
                                        radius: parent.radius

                                        Behavior on border.width {
                                            NumberAnimation {
                                                duration: Theme.shortDuration
                                                easing.type: Theme.standardEasing
                                            }
                                        }
                                    }

                                    Rectangle {
                                        id: maskRect
                                        width: thumbnailImage.width
                                        height: thumbnailImage.height
                                        radius: Theme.cornerRadius
                                        visible: false
                                        layer.enabled: true
                                    }

                                    Image {
                                        id: thumbnailImage
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        visible: status === Image.Ready
                                        asynchronous: true
                                        cache: true

                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1.0
                                            maskSource: maskRect
                                        }

                                        property string videoPath: modelData
                                        property string thumbnailPath: ""

                                        Component.onCompleted: {
                                            root.queueThumbnail(videoPath, () => {
                                                generateThumbnail()
                                            })
                                        }

                                        function generateThumbnail() {
                                            const cacheHome = StandardPaths.writableLocation(StandardPaths.GenericCacheLocation).toString().replace("file://", "")
                                            const cacheDir = cacheHome + "/DankMaterialShell/mpvpaper_thumbnails"
                                            
                                            const hash = videoPath.split('').reduce((a, b) => {
                                                a = ((a << 5) - a) + b.charCodeAt(0)
                                                return a & a
                                            }, 0)
                                            
                                            thumbnailPath = cacheDir + "/" + Math.abs(hash) + "_thumb.jpg"
                                            
                                            thumbCheckProcess.thumbnailPath = thumbnailPath
                                            thumbCheckProcess.videoPath = videoPath
                                            thumbCheckProcess.cacheDir = cacheDir
                                            thumbCheckProcess.command = ["test", "-f", thumbnailPath]
                                            thumbCheckProcess.running = true
                                        }

                                        Process {
                                            id: thumbCheckProcess
                                            property string thumbnailPath: ""
                                            property string videoPath: ""
                                            property string cacheDir: ""

                                            onExited: (code) => {
                                                if (code === 0) {
                                                    thumbnailImage.source = "file://" + thumbnailPath
                                                    root.processNextThumbnail() // 处理下一个
                                                } else {
                                                    thumbGenProcess.thumbnailPath = thumbnailPath
                                                    thumbGenProcess.videoPath = videoPath
                                                    thumbGenProcess.cacheDir = cacheDir
                                                    thumbGenProcess.command = ["bash", "-c",
                                                        `mkdir -p "${cacheDir}" && ffmpeg -i "${videoPath}" -ss 00:00:01 -vframes 1 -vf "scale=320:180:force_original_aspect_ratio=decrease,pad=320:180:(ow-iw)/2:(oh-ih)/2" -q:v 3 "${thumbnailPath}" -y 2>/dev/null`
                                                    ]
                                                    thumbGenProcess.running = true
                                                }
                                            }
                                        }

                                        Process {
                                            id: thumbGenProcess
                                            property string thumbnailPath: ""
                                            property string videoPath: ""
                                            property string cacheDir: ""

                                            onExited: (code) => {
                                                if (code === 0) {
                                                    thumbnailImage.source = "file://" + thumbnailPath
                                                } else {
                                                    console.warn("MpvPaper Widget: Failed to generate thumbnail for", videoPath, "exit code:", code)
                                                }
                                                root.processNextThumbnail() // 处理下一个
                                            }
                                        }
                                    }

                                    DankIcon {
                                        anchors.centerIn: parent
                                        name: "movie"
                                        size: 32
                                        color: Theme.primary
                                        visible: thumbnailImage.status !== Image.Ready
                                    }

                                    StateLayer {
                                        anchors.fill: parent
                                        cornerRadius: parent.radius
                                        stateColor: Theme.primary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor

                                        onClicked: {
                                            root.gridIndex = index
                                            if (modelData) {
                                                root.setCurrentVideo(modelData)
                                                ToastService.showInfo("壁纸已切换", "")
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.getPlaylist().length === 0
                            text: "暂无壁纸\n\n点击下方文件夹图标添加"
                            font.pixelSize: 14
                            color: Theme.outline
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    // Navigation bar
                    Column {
                        width: parent.width
                        height: 50

                        Row {
                            width: parent.width
                            height: 32
                            spacing: Theme.spacingS

                            Item {
                                width: (parent.width - controlsRow.width - addButton.width - Theme.spacingS) / 2
                                height: parent.height
                            }

                            Row {
                                id: controlsRow
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Theme.spacingS

                                DankActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "skip_previous"
                                    iconSize: 20
                                    buttonSize: 32
                                    enabled: root.currentPage > 0
                                    opacity: enabled ? 1.0 : 0.3
                                    onClicked: {
                                        if (root.currentPage > 0) {
                                            root.currentPage--
                                            root.gridIndex = 0
                                        }
                                    }
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: {
                                        root.refreshTrigger
                                        const playlist = root.getPlaylist()
                                        if (playlist.length === 0) return "暂无壁纸"
                                        if (root.totalPages > 1) {
                                            return `第 ${root.currentPage + 1}/${root.totalPages} 页`
                                        }
                                        return `${playlist.length} 个壁纸`
                                    }
                                    font.pixelSize: 14
                                    color: Theme.surfaceText
                                    opacity: 0.7
                                }

                                DankActionButton {
                                    anchors.verticalCenter: parent.verticalCenter
                                    iconName: "skip_next"
                                    iconSize: 20
                                    buttonSize: 32
                                    enabled: root.currentPage < root.totalPages - 1
                                    opacity: enabled ? 1.0 : 0.3
                                    onClicked: {
                                        if (root.currentPage < root.totalPages - 1) {
                                            root.currentPage++
                                            root.gridIndex = 0
                                        }
                                    }
                                }
                            }

                            DankActionButton {
                                id: addButton
                                anchors.verticalCenter: parent.verticalCenter
                                iconName: "folder_open"
                                iconSize: 20
                                buttonSize: 32
                                opacity: 0.7
                                onClicked: root.openSystemFilePicker()
                            }
                        }
                    }
                }
            }
        }
    }

    popoutWidth: 700
    popoutHeight: 410
}
