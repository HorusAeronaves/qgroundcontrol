/****************************************************************************
 *
 *   (c) 2009-2016 QGROUNDCONTROL PROJECT <http://www.qgroundcontrol.org>
 *
 * QGroundControl is licensed according to the terms in the file
 * COPYING.md in the root of the source code directory.
 *
 ****************************************************************************/


import QtQuick          2.3
import QtQuick.Controls 1.2
import QtQuick.Controls 2.2 as QC
import QtQuick.Controls.Styles 1.4
import QtQuick.Dialogs  1.2
import QtLocation       5.3
import QtPositioning    5.3
import QtQuick.Layouts  1.2

import QGroundControl               1.0
import QGroundControl.FlightMap     1.0
import QGroundControl.ScreenTools   1.0
import QGroundControl.Controls      1.0
import QGroundControl.FactSystem    1.0
import QGroundControl.FactControls  1.0
import QGroundControl.Palette       1.0
import QGroundControl.Mavlink       1.0
import QGroundControl.Controllers   1.0
import QGroundControl.Vehicle       1.0

/// Mission Editor

QGCView {
    id:         _qgcView
    viewPanel:  panel
    z:          QGroundControl.zOrderTopMost

    readonly property int       _decimalPlaces:         8
    readonly property real      _horizontalMargin:      ScreenTools.defaultFontPixelWidth  / 2
    readonly property real      _margin:                ScreenTools.defaultFontPixelHeight * 0.5
    readonly property var       _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    readonly property real      _rightPanelWidth:       Math.min(parent.width / 3, ScreenTools.defaultFontPixelWidth * 30)
    readonly property real      _toolButtonTopMargin:   parent.height - ScreenTools.availableHeight + (ScreenTools.defaultFontPixelHeight / 2)
    readonly property var       _defaultVehicleCoordinate:   QtPositioning.coordinate(37.803784, -122.462276)

    property var    _planMasterController:      masterController
    property var    _missionController:         _planMasterController.missionController
    property var    _geoFenceController:        _planMasterController.geoFenceController
    property var    _rallyPointController:      _planMasterController.rallyPointController
    property var    _visualItems:               _missionController.visualItems
    property var    _currentMissionItem
    property int    _currentMissionIndex:       0
    property bool   _lightWidgetBorders:        editorMap.isSatelliteMap
    property bool   _addWaypointOnClick:        false
    property bool   _singleComplexItem:         _missionController.complexMissionItemNames.length === 1
    property real   _toolbarHeight:             _qgcView.height - ScreenTools.availableHeight
    property int    _editingLayer:              _layerMission

    property int    _cameraIndex:       1
    property int    _gridTypeCamera:    1
    property real   _fieldWidth:        ScreenTools.defaultFontPixelWidth * 10.5
    property var    _cameraList:        []
    property var    _vehicle:           QGroundControl.multiVehicleManager.activeVehicle ? QGroundControl.multiVehicleManager.activeVehicle : QGroundControl.multiVehicleManager.offlineEditingVehicle
    property var    _vehicleCameraList: _vehicle ? _vehicle.staticCameraList : []

    readonly property int       _layerMission:              1
    readonly property int       _layerGeoFence:             2
    readonly property int       _layerRallyPoints:          3
    readonly property string    _armedVehicleUploadPrompt:  qsTr("Vehicle is currently armed. Do you want to upload the mission to the vehicle?")
    property var missionItem:      object

    property var droneName:  "verok"

    Component.onCompleted: {
        toolbar.planMasterController =  Qt.binding(function () { return _planMasterController })
        toolbar.currentMissionItem =    Qt.binding(function () { return _currentMissionItem })

        for (var i=0; i<_vehicleCameraList.length; i++) {
            _cameraList.push(_vehicleCameraList[i].name)
        }
        gridTypeCombo.model = _cameraList
        if (missionItem.manualGrid.value) {
            gridTypeCombo.currentIndex = _gridTypeManual
        } else {
            var index = -1
            for (index=0; index<_cameraList.length; index++) {
                if (_cameraList[index] == missionItem.camera.value) {
                    break;
                }
            }
            missionItem.cameraOrientationFixed = false
            if (index == _cameraList.length) {
                gridTypeCombo.currentIndex = _gridTypeCustomCamera
            } else {
                gridTypeCombo.currentIndex = index
                if (index != 1) {
                    // Specific camera is selected
                    var camera = _vehicleCameraList[index - _gridTypeCamera]
                    missionItem.cameraOrientationFixed = camera.fixedOrientation
                    missionItem.cameraMinTriggerInterval = camera.minTriggerInterval
                }
            }
        }
    }


    // Converts from degrees to radians.
    function rad(degrees) {
        return degrees * Math.PI / 180;
    }

    // Converts from radians to degrees.
    function deg(radians) {
        return radians * 180 / Math.PI;
    }

    //Based on QGeoCoordinate
    function point2PointFromDisntaceAndAzimuth(coord, coord2, distance, azimuth) {
        var latRad = rad(coord.latitude)
        var longRad = rad(coord.longitude)
        var cosLatRad = Math.cos(latRad)
        var sinLatRad = Math.sin(latRad)
        var azimuthRad = rad(azimuth)

        var ratio = (distance / (6371.0072 * 1000.0))
        var cosRatio = Math.cos(ratio)
        var sinRatio = Math.sin(ratio)

        var resultLatRad = Math.asin(sinLatRad * cosRatio + cosLatRad * sinRatio * Math.cos(azimuthRad))
        var resultLonRad = longRad + Math.atan2(Math.sin(azimuthRad) * sinRatio * cosLatRad, cosRatio - sinLatRad * Math.sin(resultLatRad))
        coord2.latitude = deg(resultLatRad)
        coord2.longitude = deg(resultLonRad)
        return coord2
    }

    function getImagePathFromDrone(name) {
        return "/res/renders/" + name + ".png"
    }

    function addComplexItem(complexItemName) {
        var coordinate = editorMap.center
        coordinate.latitude = coordinate.latitude.toFixed(_decimalPlaces)
        coordinate.longitude = coordinate.longitude.toFixed(_decimalPlaces)
        coordinate.altitude = coordinate.altitude.toFixed(_decimalPlaces)
        insertComplexMissionItem(complexItemName, coordinate, _missionController.visualItems.count)
    }

    function insertComplexMissionItem(complexItemName, coordinate, index) {
        var sequenceNumber = _missionController.insertComplexMissionItem(complexItemName, coordinate, index)
        setCurrentItem(sequenceNumber, true)
    }

    property bool _firstMissionLoadComplete:    false
    property bool _firstFenceLoadComplete:      false
    property bool _firstRallyLoadComplete:      false
    property bool _firstLoadComplete:           false

    MapFitFunctions {
        id:                         mapFitFunctions
        map:                        editorMap
        usePlannedHomePosition:     true
        planMasterController:       _planMasterController
    }

    Connections {
        target: QGroundControl.settingsManager.appSettings.defaultMissionItemAltitude

        onRawValueChanged: {
            if (_visualItems.count > 1) {
                _qgcView.showDialog(applyNewAltitude, qsTr("Apply new alititude"), showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
            }
        }
    }

    Component {
        id: applyNewAltitude

        QGCViewMessage {
            message:    qsTr("You have changed the default altitude for mission items. Would you like to apply that altitude to all the items in the current mission?")

            function accept() {
                hideDialog()
                _missionController.applyDefaultMissionAltitude()
            }
        }
    }

    Component {
        id: activeMissionUploadDialogComponent

        QGCViewDialog {

            Column {
                anchors.fill:   parent
                spacing:        ScreenTools.defaultFontPixelHeight

                QGCLabel {
                    width:      parent.width
                    wrapMode:   Text.WordWrap
                    text:       qsTr("Your vehicle is currently flying a mission. In order to upload a new or modified mission the current mission will be paused.")
                }

                QGCLabel {
                    width:      parent.width
                    wrapMode:   Text.WordWrap
                    text:       qsTr("After the mission is uploaded you can adjust the current waypoint and start the mission.")
                }

                QGCButton {
                    text:       qsTr("Pause and Upload")
                    onClicked: {
                        _activeVehicle.flightMode = _activeVehicle.pauseFlightMode
                        _planMasterController.sendToVehicle()
                        hideDialog()
                    }
                }
            }
        }
    }

    PlanMasterController {
        id: masterController

        Component.onCompleted: {
            start(true /* editMode */)
        }

        function upload() {
            if (_activeVehicle && _activeVehicle.armed && _activeVehicle.flightMode === _activeVehicle.missionFlightMode) {
                _qgcView.showDialog(activeMissionUploadDialogComponent, qsTr("Plan Upload"), _qgcView.showDialogDefaultWidth, StandardButton.Cancel)
            } else {
                sendToVehicle()
            }
        }

        function loadFromSelectedFile() {
            fileDialog.title =          qsTr("Select Plan File")
            fileDialog.selectExisting = true
            fileDialog.nameFilters =    masterController.loadNameFilters
            fileDialog.openForLoad()
        }

        function saveToSelectedFile() {
            fileDialog.title =          qsTr("Save Plan")
            fileDialog.plan =           true
            fileDialog.selectExisting = false
            fileDialog.nameFilters =    masterController.saveNameFilters
            fileDialog.openForSave()
        }

        function fitViewportToItems() {
            mapFitFunctions.fitMapViewportToMissionItems()
        }

        function saveKmlToSelectedFile() {
            fileDialog.title =          qsTr("Save KML")
            fileDialog.plan =           false
            fileDialog.selectExisting = false
            fileDialog.nameFilters =    masterController.saveKmlFilters
            fileDialog.openForSave()
        }
    }

    Connections {
        target: _missionController

        onNewItemsFromVehicle: {
            if (_visualItems && _visualItems.count != 1) {
                mapFitFunctions.fitMapViewportToMissionItems()
            }
        }
    }

    QGCPalette { id: qgcPal; colorGroupEnabled: enabled }

    ExclusiveGroup {
        id: _mapTypeButtonsExclusiveGroup
    }

    /// Sets a new current mission item
    ///     @param sequenceNumber - index for new item, -1 to clear current item
    function setCurrentItem(sequenceNumber, force) {
        if (force || sequenceNumber !== _currentMissionIndex) {
            _currentMissionItem = undefined
            _currentMissionIndex = -1
            for (var i=0; i<_visualItems.count; i++) {
                var visualItem = _visualItems.get(i)
                if (visualItem.sequenceNumber == sequenceNumber) {
                    _currentMissionItem = visualItem
                    _currentMissionItem.isCurrentItem = true
                    _currentMissionIndex = sequenceNumber
                } else {
                    visualItem.isCurrentItem = false
                }
            }
        }
    }

    /// Inserts a new simple mission item
    ///     @param coordinate Location to insert item
    ///     @param index Insert item at this index
    function insertSimpleMissionItem(coordinate, index) {
        var sequenceNumber = _missionController.insertSimpleMissionItem(coordinate, index)
        setCurrentItem(sequenceNumber, true)
    }

    property int _moveDialogMissionItemIndex

    QGCFileDialog {
        id:             fileDialog
        qgcView:        _qgcView
        property var plan:           true
        folder:         QGroundControl.settingsManager.appSettings.missionSavePath
        fileExtension:  QGroundControl.settingsManager.appSettings.planFileExtension
        fileExtension2: QGroundControl.settingsManager.appSettings.missionFileExtension

        onAcceptedForSave: {
            plan ? masterController.saveToFile(file) : masterController.saveToKml(file)
            close()
        }

        onAcceptedForLoad: {
            masterController.loadFromFile(file)
            masterController.fitViewportToItems()
            setCurrentItem(0, true)
            close()
        }
    }

    Component {
        id: moveDialog

        QGCViewDialog {
            function accept() {
                var toIndex = toCombo.currentIndex

                if (toIndex == 0) {
                    toIndex = 1
                }
                _missionController.moveMissionItem(_moveDialogMissionItemIndex, toIndex)
                hideDialog()
            }

            Column {
                anchors.left:   parent.left
                anchors.right:  parent.right
                spacing:        ScreenTools.defaultFontPixelHeight

                QGCLabel {
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    wrapMode:       Text.WordWrap
                    text:           qsTr("Move the selected mission item to the be after following mission item:")
                }

                QGCComboBox {
                    id:             toCombo
                    model:          _visualItems.count
                    currentIndex:   _moveDialogMissionItemIndex
                }
            }
        }
    }

    QGCViewPanel {
        id:             panel
        anchors.fill:   parent

        FlightMap {
            id:                         editorMap
            anchors.fill:               parent
            mapName:                    "MissionEditor"
            allowGCSLocationCenter:     true
            allowVehicleLocationCenter: true
            planView:                   true

            // This is the center rectangle of the map which is not obscured by tools
            property rect centerViewport: Qt.rect(_leftToolWidth, _toolbarHeight, editorMap.width - _leftToolWidth - _rightPanelWidth, editorMap.height - _statusHeight - _toolbarHeight)

            property real _leftToolWidth:   toolStrip.x + toolStrip.width
            property real _statusHeight:    waypointValuesDisplay.visible ? editorMap.height - waypointValuesDisplay.y : 0

            readonly property real animationDuration: 500

            // Initial map position duplicates Fly view position
            Component.onCompleted: editorMap.center = QGroundControl.flightMapPosition

            Behavior on zoomLevel {
                NumberAnimation {
                    duration:       editorMap.animationDuration
                    easing.type:    Easing.InOutQuad
                }
            }

            QGCMapPalette { id: mapPal; lightColors: editorMap.isSatelliteMap }

            MouseArea {
                //-- It's a whole lot faster to just fill parent and deal with top offset below
                //   than computing the coordinate offset.
                anchors.fill: parent
                onClicked: {
                    //-- Don't pay attention to items beneath the toolbar.
                    var topLimit = parent.height - ScreenTools.availableHeight
                    if(mouse.y < topLimit) {
                        return
                    }

                    var coordinate = editorMap.toCoordinate(Qt.point(mouse.x, mouse.y), false /* clipToViewPort */)
                    coordinate.latitude = coordinate.latitude.toFixed(_decimalPlaces)
                    coordinate.longitude = coordinate.longitude.toFixed(_decimalPlaces)
                    coordinate.altitude = coordinate.altitude.toFixed(_decimalPlaces)

                    switch (_editingLayer) {
                    case _layerMission:
                        if (_addWaypointOnClick) {
                            insertSimpleMissionItem(coordinate, _missionController.visualItems.count)
                        }
                        break
                    case _layerRallyPoints:
                        if (_rallyPointController.supported) {
                            _rallyPointController.addPoint(coordinate)
                        }
                        break
                    }
                }
            }

            // Add the mission item visuals to the map
            Repeater {
                model: _editingLayer == _layerMission ? _missionController.visualItems : undefined

                delegate: MissionItemMapVisual {
                    map:        editorMap
                    onClicked:  setCurrentItem(sequenceNumber, false)
                    visible:    _editingLayer == _layerMission
                }
            }

            // Add lines between waypoints
            MissionLineView {
                model: _editingLayer == _layerMission ? _missionController.waypointLines : undefined
            }

            // Add the vehicles to the map
            MapItemView {
                model: QGroundControl.multiVehicleManager.vehicles
                delegate:
                    VehicleMapItem {
                    vehicle:        object
                    coordinate:     object.coordinate
                    map:            editorMap
                    size:           ScreenTools.defaultFontPixelHeight * 3
                    z:              QGroundControl.zOrderMapItems - 1
                }
            }

            GeoFenceMapVisuals {
                map:                    editorMap
                myGeoFenceController:   _geoFenceController
                interactive:            _editingLayer == _layerGeoFence
                homePosition:           _missionController.plannedHomePosition
                planView:               true
            }

            RallyPointMapVisuals {
                map:                    editorMap
                myRallyPointController: _rallyPointController
                interactive:            _editingLayer == _layerRallyPoints
                planView:               true
            }

            ToolStrip {
                id:                 toolStrip
                anchors.leftMargin: ScreenTools.defaultFontPixelWidth
                anchors.left:       parent.left
                anchors.topMargin:  _toolButtonTopMargin
                anchors.top:        parent.top
                color:              qgcPal.window
                title:              qsTr("Plan")
                z:                  QGroundControl.zOrderWidgets
                showAlternateIcon:  [ false, false, masterController.dirty, false, false, false, false ]
                rotateImage:        [ false, false, masterController.syncInProgress, false, false, false, false ]
                animateImage:       [ false, false, masterController.dirty, false, false, false, false ]
                buttonEnabled:      [ true, true, !masterController.syncInProgress, true, true, true, true ]
                buttonVisible:      [ true, true, true, true, _showZoom, _showZoom, true ]
                maxHeight:          mapScale.y - toolStrip.y

                property bool _showZoom: !ScreenTools.isMobile

                model: [
                    {
                        name:       "Waypoint",
                        iconSource: "/qmlimages/MapAddMission.svg",
                        toggle:     true
                    },
                    {
                        name:               _singleComplexItem ? _missionController.complexMissionItemNames[0] : "Pattern",
                        iconSource:         "/qmlimages/MapDrawShape.svg",
                        dropPanelComponent: _singleComplexItem ? undefined : patternDropPanel
                    },
                    {
                        name:                   "Sync",
                        iconSource:             "/qmlimages/MapSync.svg",
                        alternateIconSource:    "/qmlimages/MapSyncChanged.svg",
                        dropPanelComponent:     syncDropPanel
                    },
                    {
                        name:               "Center",
                        iconSource:         "/qmlimages/MapCenter.svg",
                        dropPanelComponent: centerMapDropPanel
                    },
                    {
                        name:               "In",
                        iconSource:         "/qmlimages/ZoomPlus.svg"
                    },
                    {
                        name:               "Out",
                        iconSource:         "/qmlimages/ZoomMinus.svg"
                    },
                    {
                        name:               "Horus",
                        iconSource:         "/qmlimages/horus-icon.svg",
                    }
                ]

                onClicked: {
                    switch (index) {
                    case 0:
                        _addWaypointOnClick = checked
                        break
                    case 1:
                        if (_singleComplexItem) {
                            addComplexItem(_missionController.complexMissionItemNames[0])
                        }
                        break
                    case 4:
                        editorMap.zoomLevel += 0.5
                        break
                    case 5:
                        editorMap.zoomLevel -= 0.5
                        break
                    case 6:
                        // Load mission
                        masterController.loadFromFileGeo("/horus.plan", editorMap.center)
                        masterController.fitViewportToItems()

                        setCurrentItem(3, true)
                        missionItem = _currentMissionItem

                        popup.open()

                        break
                    }
                }
            }
        } // FlightMap

        QC.Popup {
            id: popup
            modal: true
            focus: true
            clip: true
            x: (parent.width - width)/2
            y: (parent.height - height)/2
            closePolicy: QC.Popup.CloseOnEscape | QC.Popup.CloseOnPressOutsideParent

            background: Rectangle {
                border.color: qgcPal.windowShade
                color: qgcPal.window
                radius: 10
            }

            GridLayout {
                id: lay
                columns: 3

                Image {
                    id: uavImage
                    anchors.top:  parent.top
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    Layout.preferredWidth: _qgcView._fieldWidth
                    Layout.fillWidth: true
                    fillMode: Image.PreserveAspectFit
                    height: uavImage.width / 3
                    source: getImagePathFromDrone(droneName)

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            droneName  = droneName == "verok" ? "maptor" : "verok"
                        }
                    }
                }

                QGCComboBox {
                    id:             gridTypeCombo
                    model:          _cameraList
                    Layout.fillWidth: true
                    Layout.columnSpan: 3
                    currentIndex:   -1

                    onActivated: {
                        missionItem.manualGrid.value = false
                        missionItem.CameraIndex = index + 2
                        missionItem.camera.value = gridTypeCombo.textAt(index + 2)
                        var listIndex = index - _gridTypeCamera + 2
                        missionItem.cameraSensorWidth.rawValue          = _vehicleCameraList[listIndex].sensorWidth
                        missionItem.cameraSensorHeight.rawValue         = _vehicleCameraList[listIndex].sensorHeight
                        missionItem.cameraResolutionWidth.rawValue      = _vehicleCameraList[listIndex].imageWidth
                        missionItem.cameraResolutionHeight.rawValue     = _vehicleCameraList[listIndex].imageHeight
                        missionItem.cameraFocalLength.rawValue          = _vehicleCameraList[listIndex].focalLength
                        missionItem.cameraOrientationLandscape.rawValue = _vehicleCameraList[listIndex].landscape ? 1 : 0
                        missionItem.cameraOrientationFixed              = _vehicleCameraList[listIndex].fixedOrientation
                        missionItem.cameraMinTriggerInterval            = _vehicleCameraList[listIndex].minTriggerInterval
                    }
                }

                RowLayout {
                    id: surveyLay
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    spacing:        _margin
                    Layout.columnSpan: 3

                    Item { Layout.fillWidth: true }
                    QGCLabel {
                        id: frontLapLabel
                        Layout.preferredWidth:  _qgcView._fieldWidth
                        text:                   qsTr("Front Lap")
                    }
                    QGCLabel {
                        Layout.preferredWidth:  _qgcView._fieldWidth
                        text:                   qsTr("Side Lap")
                    }
                }

                RowLayout {
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    Layout.columnSpan: 3

                    spacing:        _margin
                    QGCLabel { text: qsTr("Overlap"); Layout.fillWidth: true }
                    FactTextField {
                        Layout.preferredWidth:  _qgcView._fieldWidth
                        fact:                   missionItem.frontalOverlap
                    }
                    FactTextField {
                        Layout.preferredWidth:  _qgcView._fieldWidth
                        fact:                   missionItem.sideOverlap
                    }
                }

                FactCheckBox {
                    text:       qsTr("Hover and capture image")
                    fact:       missionItem.hoverAndCapture
                    visible:    missionItem.hoverAndCaptureAllowed
                    Layout.columnSpan: 3
                    onClicked: {
                        if (checked) {
                            missionItem.cameraTriggerInTurnaround.rawValue = false
                        }
                    }
                }

                FactCheckBox {
                    text:       qsTr("Take images in turnarounds")
                    fact:       missionItem.cameraTriggerInTurnaround
                    enabled:    !missionItem.hoverAndCapture.rawValue
                    Layout.columnSpan: 3
                }

                SectionHeader {
                    id:     gridHeader
                    text:   qsTr("Grid")
                    Layout.columnSpan: 3
                    enabled: false
                }

                GridLayout {
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    columnSpacing:  _margin
                    rowSpacing:     _margin
                    columns:        2
                    visible:        gridHeader.checked

                    GridLayout {
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        columnSpacing:  _margin
                        rowSpacing:     _margin
                        columns:        2
                        visible:        gridHeader.checked

                        QGCLabel {
                            id:                 angleText
                            text:               qsTr("Angle")
                            Layout.fillWidth:   true
                        }

                        ToolButton {
                            id:                     windRoseButton
                            anchors.verticalCenter: angleText.verticalCenter
                            iconSource:             qgcPal.globalTheme === QGCPalette.Light ? "/res/wind-roseBlack.svg" : "/res/wind-rose.svg"
                            visible:                _vehicle.fixedWing

                            onClicked: {
                                windRosePie.angle = Number(gridAngleText.text)
                                var cords = windRoseButton.mapToItem(_qgcView, 0, 0)
                                windRosePie.popup(cords.x + windRoseButton.width / 2, cords.y + windRoseButton.height / 2)
                            }
                        }
                    }

                    FactTextField {
                        id:                 gridAngleText
                        fact:               missionItem.gridAngle
                        Layout.fillWidth:   true
                    }

                    QGCLabel { text: qsTr("Turnaround dist") }
                    FactTextField {
                        fact:                   missionItem.turnaroundDist
                        Layout.fillWidth:       true
                    }

                    QGCCheckBox {
                        text:               qsTr("Refly at 90 degree offset")
                        checked:            missionItem.refly90Degrees
                        onClicked:          missionItem.refly90Degrees = checked
                        Layout.columnSpan:  2
                    }

                    QGCLabel {
                        wrapMode:               Text.WordWrap
                        text:                   qsTr("Select one:")
                        Layout.preferredWidth:  _qgcView._fieldWidth
                        Layout.columnSpan:      2
                    }

                    QGCRadioButton {
                        id:                     fixedAltitudeRadio
                        text:                   qsTr("Altitude")
                        checked:                !!missionItem.fixedValueIsAltitude.value
                        exclusiveGroup:         fixedValueGroup
                        onClicked: {
                            missionItem.fixedValueIsAltitude.value = 1
                            fixedGroundResolutionRadio.checked = false
                        }
                    }

                    FactTextField {
                        fact:                   missionItem.gridAltitude
                        enabled:                fixedAltitudeRadio.checked
                        Layout.fillWidth:       true
                    }

                    QGCRadioButton {
                        id:                     fixedGroundResolutionRadio
                        text:                   qsTr("Ground res")
                        checked:                !missionItem.fixedValueIsAltitude.value
                        exclusiveGroup:         fixedValueGroup
                        onClicked: {
                            missionItem.fixedValueIsAltitude.value = 0
                            fixedAltitudeRadio.checked = false
                        }
                    }

                    FactTextField {
                        fact:                   missionItem.groundResolution
                        enabled:                fixedGroundResolutionRadio.checked
                        Layout.fillWidth:       true
                    }
                }

                Button {
                    id: genBt
                    text: "Generate mission"
                    Layout.columnSpan: 3
                    Layout.fillWidth: true

                    onClicked: {
                        var loiterInAlt = droneName == "verok" ? 150 : 60
                        var lastIndex = _visualItems.count - 1
                        var angle = windRosePie.angle - 90
                        _visualItems.get(2).coordinate.altitude = loiterInAlt
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(3).coordinate, _visualItems.get(2).coordinate, 500, angle)
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(2).coordinate, _visualItems.get(1).coordinate, 500, angle)
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(1).coordinate, _visualItems.get(0).coordinate, 0, 0)
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(lastIndex - 6).exitCoordinate, _visualItems.get(lastIndex - 5).coordinate, 500, 90)

                        point2PointFromDisntaceAndAzimuth(_visualItems.get(1).coordinate, _visualItems.get(lastIndex).coordinate, 10, angle)
                        var altDiff = Math.abs(_visualItems.get(lastIndex - 1).coordinate.altitude - _visualItems.get(lastIndex).coordinate.altitude)*10
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(lastIndex).coordinate, _visualItems.get(lastIndex - 1).coordinate, altDiff, angle)
                        altDiff = Math.abs(_visualItems.get(lastIndex - 1).coordinate.altitude - _visualItems.get(lastIndex - 2).coordinate.altitude)*10
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(lastIndex - 1).coordinate, _visualItems.get(lastIndex - 2).coordinate, altDiff, angle)
                        altDiff = Math.abs(_visualItems.get(lastIndex - 2).coordinate.altitude - _visualItems.get(lastIndex - 3).coordinate.altitude)*10
                        point2PointFromDisntaceAndAzimuth(_visualItems.get(lastIndex - 2).coordinate, _visualItems.get(lastIndex - 3).coordinate, altDiff, angle)

                        popup.close()
                    }
                }
            }
        }

        // Right pane for mission editing controls
        Rectangle {
            id:                 rightPanel
            anchors.bottom:     parent.bottom
            anchors.right:      parent.right
            height:             ScreenTools.availableHeight
            width:              _rightPanelWidth
            color:              qgcPal.window
            opacity:            0.2
        }

        Item {
            anchors.fill:   rightPanel

            // Plan Element selector (Mission/Fence/Rally)
            Row {
                id:                 planElementSelectorRow
                anchors.topMargin:  Math.round(ScreenTools.defaultFontPixelHeight / 3)
                anchors.top:        parent.top
                anchors.left:       parent.left
                anchors.right:      parent.right
                spacing:            _horizontalMargin
                visible:            QGroundControl.corePlugin.options.enablePlanViewSelector

                readonly property real _buttonRadius: ScreenTools.defaultFontPixelHeight * 0.75

                ExclusiveGroup {
                    id: planElementSelectorGroup
                    onCurrentChanged: {
                        switch (current) {
                        case planElementMission:
                            _editingLayer = _layerMission
                            break
                        case planElementGeoFence:
                            _editingLayer = _layerGeoFence
                            break
                        case planElementRallyPoints:
                            _editingLayer = _layerRallyPoints
                            break
                        }
                    }
                }

                QGCRadioButton {
                    id:             planElementMission
                    exclusiveGroup: planElementSelectorGroup
                    text:           qsTr("Mission")
                    checked:        true
                    color:          mapPal.text
                    textStyle:      Text.Outline
                    textStyleColor: mapPal.textOutline
                }

                Item { height: 1; width: 1 }

                QGCRadioButton {
                    id:             planElementGeoFence
                    exclusiveGroup: planElementSelectorGroup
                    text:           qsTr("Fence")
                    color:          mapPal.text
                    textStyle:      Text.Outline
                    textStyleColor: mapPal.textOutline
                }

                Item { height: 1; width: 1 }

                QGCRadioButton {
                    id:             planElementRallyPoints
                    exclusiveGroup: planElementSelectorGroup
                    text:           qsTr("Rally")
                    color:          mapPal.text
                    textStyle:      Text.Outline
                    textStyleColor: mapPal.textOutline
                }
            } // Row - Plan Element Selector

            // Mission Item Editor
            Item {
                id:                 missionItemEditor
                anchors.topMargin:  ScreenTools.defaultFontPixelHeight / 2
                anchors.top:        planElementSelectorRow.visible ? planElementSelectorRow.bottom : planElementSelectorRow.top
                anchors.left:       parent.left
                anchors.right:      parent.right
                anchors.bottom:     parent.bottom
                visible:            _editingLayer == _layerMission

                QGCListView {
                    id:             missionItemEditorListView
                    anchors.fill:   parent
                    spacing:        _margin / 2
                    orientation:    ListView.Vertical
                    model:          _missionController.visualItems
                    cacheBuffer:    Math.max(height * 2, 0)
                    clip:           true
                    currentIndex:   _currentMissionIndex
                    highlightMoveDuration: 250

                    delegate: MissionItemEditor {
                        map:                editorMap
                        masterController:  _planMasterController
                        missionItem:        object
                        width:              parent.width
                        readOnly:           false
                        rootQgcView:        _qgcView

                        onClicked:  setCurrentItem(object.sequenceNumber, false)

                        onRemove: {
                            var removeIndex = index
                            _missionController.removeMissionItem(removeIndex)
                            if (removeIndex >= _missionController.visualItems.count) {
                                removeIndex--
                            }
                            _currentMissionIndex = -1
                            rootQgcView.setCurrentItem(removeIndex, true)
                        }

                        onInsertWaypoint:       insertSimpleMissionItem(editorMap.center, index)
                        onInsertComplexItem:    insertComplexMissionItem(complexItemName, editorMap.center, index)
                    }
                } // QGCListView
            } // Item - Mission Item editor

            // GeoFence Editor
            GeoFenceEditor {
                anchors.topMargin:      ScreenTools.defaultFontPixelHeight / 2
                anchors.top:            planElementSelectorRow.bottom
                anchors.left:           parent.left
                anchors.right:          parent.right
                availableHeight:        ScreenTools.availableHeight
                myGeoFenceController:   _geoFenceController
                flightMap:              editorMap
                visible:                _editingLayer == _layerGeoFence
            }

            // Rally Point Editor

            RallyPointEditorHeader {
                id:                 rallyPointHeader
                anchors.topMargin:  ScreenTools.defaultFontPixelHeight / 2
                anchors.top:        planElementSelectorRow.bottom
                anchors.left:       parent.left
                anchors.right:      parent.right
                visible:            _editingLayer == _layerRallyPoints
                controller:         _rallyPointController
            }

            RallyPointItemEditor {
                id:                 rallyPointEditor
                anchors.topMargin:  ScreenTools.defaultFontPixelHeight / 2
                anchors.top:        rallyPointHeader.bottom
                anchors.left:       parent.left
                anchors.right:      parent.right
                visible:            _editingLayer == _layerRallyPoints && _rallyPointController.points.count
                rallyPoint:         _rallyPointController.currentRallyPoint
                controller:         _rallyPointController
            }
        } // Right panel

        MapScale {
            id:                 mapScale
            anchors.margins:    ScreenTools.defaultFontPixelHeight * (0.66)
            anchors.bottom:     waypointValuesDisplay.visible ? waypointValuesDisplay.top : parent.bottom
            anchors.left:       parent.left
            mapControl:         editorMap
            visible:            !ScreenTools.isTinyScreen
        }

        MissionItemStatus {
            id:                 waypointValuesDisplay
            anchors.margins:    ScreenTools.defaultFontPixelWidth
            anchors.left:       parent.left
            maxWidth:           parent.width - rightPanel.width - x
            anchors.bottom:     parent.bottom
            missionItems:       _missionController.visualItems
            visible:            _editingLayer === _layerMission && !ScreenTools.isShortScreen
        }
    } // QGCViewPanel

    Component {
        id: syncLoadFromVehicleOverwrite
        QGCViewMessage {
            id:         syncLoadFromVehicleCheck
            message:   qsTr("You have unsaved/unsent changes. Loading from the Vehicle will lose these changes. Are you sure you want to load from the Vehicle?")
            function accept() {
                hideDialog()
                masterController.loadFromVehicle()
            }
        }
    }

    Component {
        id: syncLoadFromFileOverwrite
        QGCViewMessage {
            id:         syncLoadFromVehicleCheck
            message:   qsTr("You have unsaved/unsent changes. Loading from a file will lose these changes. Are you sure you want to load from a file?")
            function accept() {
                hideDialog()
                masterController.loadFromSelectedFile()
            }
        }
    }

    Component {
        id: removeAllPromptDialog
        QGCViewMessage {
            message: qsTr("Are you sure you want to remove all items? ") +
                     (_planMasterController.offline ? "" : qsTr("This will also remove all items from the vehicle."))
            function accept() {
                if (_planMasterController.offline) {
                    masterController.removeAll()
                } else {
                    masterController.removeAllFromVehicle()
                }
                hideDialog()
            }
        }
    }

    //- ToolStrip DropPanel Components

    Component {
        id: centerMapDropPanel

        CenterMapDropPanel {
            map:            editorMap
            fitFunctions:   mapFitFunctions
        }
    }

    Component {
        id: patternDropPanel

        ColumnLayout {
            spacing:    ScreenTools.defaultFontPixelWidth * 0.5

            QGCLabel { text: qsTr("Create complex pattern:") }

            Repeater {
                model: _missionController.complexMissionItemNames

                QGCButton {
                    text:               modelData
                    Layout.fillWidth:   true

                    onClicked: {
                        addComplexItem(modelData)
                        dropPanel.hide()
                    }
                }
            }
        } // Column
    }

    Component {
        id: syncDropPanel

        Column {
            id:         columnHolder
            spacing:    _margin

            property string _overwriteText: (_editingLayer == _layerMission) ? qsTr("Mission overwrite") : ((_editingLayer == _layerGeoFence) ? qsTr("GeoFence overwrite") : qsTr("Rally Points overwrite"))

            QGCLabel {
                width:      sendSaveGrid.width
                wrapMode:   Text.WordWrap
                text:       masterController.dirty ?
                                qsTr("You have unsaved changes. You should upload to your vehicle, or save to a file:") :
                                qsTr("Sync:")
            }

            GridLayout {
                id:                 sendSaveGrid
                columns:            2
                anchors.margins:    _margin
                rowSpacing:         _margin
                columnSpacing:      ScreenTools.defaultFontPixelWidth

                QGCButton {
                    text:               qsTr("Upload")
                    Layout.fillWidth:   true
                    enabled:            !masterController.offline && !masterController.syncInProgress
                    onClicked: {
                        dropPanel.hide()
                        masterController.upload()
                    }
                }

                QGCButton {
                    text:               qsTr("Download")
                    Layout.fillWidth:   true
                    enabled:            !masterController.offline && !masterController.syncInProgress
                    onClicked: {
                        dropPanel.hide()
                        if (masterController.dirty) {
                            _qgcView.showDialog(syncLoadFromVehicleOverwrite, columnHolder._overwriteText, _qgcView.showDialogDefaultWidth, StandardButton.Yes | StandardButton.Cancel)
                        } else {
                            masterController.loadFromVehicle()
                        }
                    }
                }

                QGCButton {
                    text:               qsTr("Save To File...")
                    Layout.fillWidth:   true
                    enabled:            !masterController.syncInProgress
                    onClicked: {
                        dropPanel.hide()
                        masterController.saveToSelectedFile()
                    }
                }

                QGCButton {
                    text:               qsTr("Load From File...")
                    Layout.fillWidth:   true
                    enabled:            !masterController.syncInProgress
                    onClicked: {
                        dropPanel.hide()
                        if (masterController.dirty) {
                            _qgcView.showDialog(syncLoadFromFileOverwrite, columnHolder._overwriteText, _qgcView.showDialogDefaultWidth, StandardButton.Yes | StandardButton.Cancel)
                        } else {
                            masterController.loadFromSelectedFile()
                        }
                    }
                }

                QGCButton {
                    text:               qsTr("Remove All")
                    Layout.fillWidth:   true
                    onClicked:  {
                        dropPanel.hide()
                        _qgcView.showDialog(removeAllPromptDialog, qsTr("Remove all"), _qgcView.showDialogDefaultWidth, StandardButton.Yes | StandardButton.No)
                    }
                }

                QGCButton {
                    text:               qsTr("Save KML...")
                    Layout.fillWidth:   true
                    enabled:            !masterController.syncInProgress
                    onClicked: {
                        dropPanel.hide()
                        masterController.saveKmlToSelectedFile()
                    }
                }
            }
        }
    }

    QC.Popup {
        id:          windRosePie
        height:      2.6*windRoseButton.height
        width:       2.6*windRoseButton.width
        visible:     false
        focus:       true
        z:           windRoseButton.z + 1
        background: Rectangle {
            color: "transparent"
            border.color: "transparent"
        }

        property string colorCircle: qgcPal.windowShade
        property string colorBackground: qgcPal.colorGrey
        property real lineWidth: windRoseButton.width / 3
        property real angle: Number(gridAngleText.text)

        Canvas {
            id:             windRoseCanvas
            z:              windRosePie.z
            anchors.fill:   parent

            onPaint: {
                var ctx = getContext("2d")
                var x = width / 2
                var y = height / 2
                var angleWidth = 0.03 * Math.PI
                var start = windRosePie.angle*Math.PI/180 - angleWidth
                var end = windRosePie.angle*Math.PI/180 + angleWidth
                ctx.reset()

                ctx.beginPath()
                ctx.arc(x, y, (width / 3) - windRosePie.lineWidth / 2, 0, 2*Math.PI, false)
                ctx.lineWidth = windRosePie.lineWidth
                ctx.strokeStyle = windRosePie.colorBackground
                ctx.stroke()

                ctx.beginPath()
                ctx.arc(x, y, (width / 3) - windRosePie.lineWidth / 2, start, end, false)
                ctx.lineWidth = windRosePie.lineWidth
                ctx.strokeStyle = windRosePie.colorCircle
                ctx.stroke()
            }
        }

        onFocusChanged: {
            visible = focus
        }

        function popup(x, y) {
            if (x !== undefined)
                windRosePie.x = x - windRosePie.width / 2
            if (y !== undefined)
                windRosePie.y = y - windRosePie.height / 2

            windRosePie.visible = true
            windRosePie.focus = true
            missionItemEditorListView.interactive = false
        }

        MouseArea {
            id: mouseArea
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton

            onClicked: {
                windRosePie.visible = false
                missionItemEditorListView.interactive = true
            }
            onPositionChanged: {
                var point = Qt.point(mouseX - parent.width / 2, mouseY - parent.height / 2)
                var angle = Math.round(Math.atan2(point.y, point.x) * 180 / Math.PI)
                windRoseCanvas.requestPaint()
                windRosePie.angle = angle
                gridAngleText.text = angle
                gridAngleText.editingFinished()

                if(angle > -135 && angle <= -45) {
                    gridAngleBox.activated(2) // or 3
                } else if(angle > -45 && angle <= 45) {
                    gridAngleBox.activated(2) // or 0
                } else if(angle > 45 && angle <= 135) {
                    gridAngleBox.activated(1) // or 0
                } else if(angle > 135 || angle <= -135) {
                    gridAngleBox.activated(1) // or 3
                }
            }
        }

        QGCColoredImage {
            id:      windGuru
            source:  "/res/wind-guru.svg"
            visible: windRosePie.visible
            width:   windRosePie.width / 3
            height:  width * 4.28e-1
            smooth:  true
            color:   qgcPal.colorGrey
            transform: Rotation {
                origin.x: windGuru.width / 2
                origin.y: windGuru.height / 2
                axis { x: 0; y: 0; z: 1 } angle: windRosePie.angle + 180
            }
            x: Math.sin(- windRosePie.angle*Math.PI/180 - 3*Math.PI/2)*(windRosePie.width/2) + windRosePie.width / 2 - windGuru.width / 2 - windRoseButton.width / 4
            y: Math.cos(- windRosePie.angle*Math.PI/180 - 3*Math.PI/2)*(windRosePie.height/2) + windRosePie.height / 2 - windGuru.height / 2 - windRoseButton.height / 4
            z: windRosePie.z + 1
        }
    }

    FactComboBox {
        id: gridAngleBox
        fact:                   missionItem.gridEntryLocation
        visible:                !windRoseButton.visible
        indexModel:             false
        Layout.fillWidth:       true
    }
} // QGCVIew
