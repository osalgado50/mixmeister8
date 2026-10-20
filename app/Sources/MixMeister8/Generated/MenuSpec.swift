// GENERADO por tools/gen_menus.py desde docs/spec/menus-fusion.json — no editar a mano.

enum MenuSpecs {
    static let main = MenuSpec("MainMenu", [
        .item("MixMeister 8", submenu: MenuSpec("MixMeister 8", [
            .item("About MixMeister 8", action: "orderFrontStandardAboutPanel:"),
            .separator,
            .item("Preferences…", action: "preferences:", key: ",", mods: [.cmd]),
            .separator,
            .item("Services", submenu: MenuSpec("Services", [

            ])),
            .separator,
            .item("Hide MixMeister 8", action: "hide:", key: "h", mods: [.cmd]),
            .item("Hide Others", action: "hideOtherApplications:", key: "h", mods: [.opt, .cmd]),
            .item("Show All", action: "unhideAllApplications:"),
            .separator,
            .item("Quit MixMeister 8", action: "terminate:", key: "q", mods: [.cmd])
        ])),
        .item("File", submenu: MenuSpec("File", [
            .item("Add Files To Library...", action: "addFilesToLibrary:"),
            .separator,
            .item("New Playlist", action: "newPlayList:", key: "n", mods: [.cmd]),
            .item("Open Playlist...", action: "openPlayList:", key: "o", mods: [.cmd]),
            .item("Append Playlist...", action: "appendPlayList:"),
            .item("Open Recent Playlist", submenu: MenuSpec("Open Recent Playlist", [
                .item("Clear Menu", action: "clearRecentFiles:")
            ])),
            .separator,
            .item("Save Playlist", action: "savePlayList:", key: "s", mods: [.cmd]),
            .item("Save Playlist As…", action: "savePlayListAs:", key: "S", mods: [.cmd, .shift]),
            .separator,
            .item("Export Playlist to File...", action: "exportPlaylistToFile:"),
            .item("Export Playlist to iTunes...", action: "exportPlaylistToDevice:"),
            .item("Export Playlist as Mobile Mix...", action: "exportPlaylistAsMobileMix:"),
            .item("Burn CD...", action: "burnCD:"),
            .separator,
            .item("Print Library…", action: "printLibrary:"),
            .item("Print Playlist…", action: "printPlaylist:", key: "p", mods: [.cmd])
        ])),
        .item("Edit", submenu: MenuSpec("Edit", [
            .item("Undo", action: "undo:", key: "z", mods: [.cmd]),
            .item("Redo", action: "redo:", key: "Z", mods: [.cmd, .shift]),
            .separator,
            .item("Cut", action: "cut:", key: "x", mods: [.cmd]),
            .item("Copy", action: "copy:", key: "c", mods: [.cmd]),
            .item("Paste", action: "paste:", key: "v", mods: [.cmd]),
            .separator,
            .item("Delete", action: "delete:"),
            .separator,
            .item("Select All", action: "selectAll:", key: "a", mods: [.cmd])
        ])),
        .item("View", submenu: MenuSpec("View", [
            .item("Library", action: "viewLibrary:"),
            .item("Effects", action: "viewEffects:"),
            .separator,
            .item("Song Slicer", action: "viewSongSlicer:"),
            .item("Effects Rack", action: "viewEffectsRack:"),
            .separator,
            .item("Zoom In", action: "zoomIn:", key: "+", mods: []),
            .item("Zoom Out", action: "zoomOut:", key: "-", mods: []),
            .separator,
            .item("Timeline Ruler", submenu: MenuSpec("Timeline Ruler", [
                .item("Time", action: "timelineRulerTime:"),
                .item("Measures and Beats", action: "timelineRulerMeasuresAndBeats:")
            ])),
            .separator,
            .item("2 Strips", action: "view2Strips:"),
            .item("4 Strips", action: "view4Strips:"),
            .item("6 Strips", action: "view6Strips:"),
            .item("8 Strips", action: "view8Strips:"),
            .separator,
            .item("Show Performed Tracks", action: "showPerformedTracks:", key: "R", mods: [.cmd, .shift])
        ])),
        .item("Library", submenu: MenuSpec("Library", [
            .item("Columns", submenu: MenuSpec("Columns", [
                .item("TITLE", action: "toggleTitle:", tag: 1),
                .item("ARTIST", action: "toggleArtist:", tag: 2),
                .item("BPM", action: "toggleBpm:", tag: 3),
                .item("ALBUM", action: "toggleAlbum:", tag: 4),
                .item("TIME", action: "toggleTime:", tag: 5),
                .item("KEY", action: "toggleKey:", tag: 6),
                .item("KEYCODE", action: "toggleKeyCode:", tag: 7),
                .item("TWEAKED", action: "toggleTweaked:", tag: 8),
                .item("YEAR", action: "toggleYear:", tag: 9),
                .item("GENRE", action: "toggleGenre:", tag: 10),
                .item("COMPOSER", action: "toggleComposer:", tag: 11),
                .item("FILENAME", action: "toggleFileName:", tag: 12),
                .item("DATE ADDED", action: "toggleDateAdded:", tag: 13),
                .item("RATING", action: "toggleRating:", tag: 14),
                .item("COMMENTS", action: "toggleComments:", tag: 15),
                .item("TRACK", action: "toggleTrack:", tag: 16),
                .item("BITRATE", action: "toggleBitRate:", tag: 17),
                .item("LABEL", action: "toggleLabel:", tag: 18),
                .item("USER 1", action: "toggleUser1:", tag: 19),
                .item("USER 2", action: "toggleUser2:", tag: 20),
                .item("PLAYLIST", action: "togglePlaylist:")
            ])),
            .separator,
            .item("New Category...", action: "newCategory:"),
            .item("Delete Category...", action: "deleteCategory:"),
            .separator,
            .item("Clean Up Library...", action: "cleanUpLibrary:"),
            .item("Import Library...", action: "importLibrary:"),
            .item("Export Library...", action: "exportLibrary:"),
            .item("Import from iTunes...", action: "importITunes:"),
            .item("Smart Playlist...", action: "smartPlaylist:")
        ])),
        .item("Playback", submenu: MenuSpec("Playback", [
            .item("Play/Pause", action: "playPause:"),
            .item("Stop", action: "stop:"),
            .item("Jog Backward", action: "jogBackward:"),
            .item("Jog Forward", action: "jogForward:"),
            .separator,
            .item("Mix Now", action: "mixNow:", key: "\u{f709}", mods: []),
            .separator,
            .item("Previous Track", action: "previousTrack:"),
            .item("Next Track", action: "nextTrack:"),
            .separator,
            .item("Drag Tempo", action: "dragTempo:", key: "[", mods: []),
            .item("Push Tempo", action: "pushTempo:", key: "]", mods: []),
            .separator,
            .item("Perform/Pause", action: "performPause:", key: "\u{f70f}", mods: []),
            .item("Fade and Cue Next", action: "stopAndCueNext:", key: "\u{f70e}", mods: []),
            .separator,
            .item("Mix Performance Now", action: "mixPerformanceNow:", key: "\u{f70d}", mods: []),
            .item("Reset Performance Position", action: "resetPerformancePosition:", key: "r", mods: [.cmd])
        ])),
        .item("Tools", submenu: MenuSpec("Tools", [
            .item("Transitions", submenu: MenuSpec("Transitions", [
                .item("Item")
            ])),
            .separator,
            .item("Snap To Beat", action: "snapToBeat:", key: "B", mods: [.cmd, .shift]),
            .item("Snap To", submenu: MenuSpec("Snap To", [
                .item("8 Measures", action: "snapTo8Measures:"),
                .item("4 Measures", action: "snapTo4Measures:"),
                .item("2 Measures", action: "snapTo2Measures:"),
                .item("1 Measure", action: "snapTo1Measure:"),
                .item("Half Note", action: "snapToHalfNote:"),
                .item("Quarter Note", action: "snapToQuarterNote:"),
                .item("Eighth Note", action: "snapToEighthNote:"),
                .item("Sixteenth Note", action: "snapToSixteenthNote:")
            ])),
            .separator,
            .item("Add To Category...", action: "handleMenuItem:", key: "g", mods: [.ctrl], tag: 2001),
            .item("Remove From Active Category...", action: "handleMenuItem:", tag: 2002),
            .item("Find Similar Tracks", action: "handleMenuItem:", key: "f", mods: [.ctrl], tag: 2003),
            .separator,
            .item("Add Volume Marker", action: "handleMenuItem:", key: "v", mods: [], tag: 2101),
            .item("Add Treble Marker", action: "handleMenuItem:", key: "t", mods: [], tag: 2102),
            .item("Add Midrange Marker", action: "handleMenuItem:", key: "m", mods: [], tag: 2103),
            .item("Add Bass Marker", action: "handleMenuItem:", key: "b", mods: [], tag: 2104),
            .separator,
            .item("Add Label Marker", action: "handleMenuItem:", key: "l", mods: [], tag: 2105),
            .item("Add Effects Parameter Marker", action: "handleMenuItem:", key: "e", mods: [], tag: 2106),
            .separator,
            .item("Add Loop Start Marker", action: "handleMenuItem:", key: "9", mods: [], tag: 2107),
            .item("Add Loop End Marker", action: "handleMenuItem:", key: "0", mods: [], tag: 2108),
            .separator,
            .item("Split Segment at Cursor", action: "handleMenuItem:", key: "s", mods: [], tag: 2109),
            .item("Reverse", action: "handleMenuItem:", tag: 2110),
            .separator,
            .item("Set As Next Performance Track", action: "handleMenuItem:", key: "n", mods: [.ctrl], tag: 2201),
            .separator,
            .item("Tweaks...", action: "handleMenuItem:", key: "w", mods: [.ctrl], tag: 2202),
            .item("Quick Save Tweak", action: "handleMenuItem:", key: "s", mods: [.ctrl], tag: 2203),
            .separator,
            .item("Edit Tag...", action: "handleMenuItem:", key: "e", mods: [.ctrl], tag: 2204),
            .item("Adjust Track Settings...", action: "handleMenuItem:", key: "t", mods: [.ctrl], tag: 2205),
            .separator,
            .item("Audio Output Configuration...", action: "doAudioSetupDialog:")
        ])),
        .item("Window", submenu: MenuSpec("Window", [
            .item("Minimize", action: "performMiniaturize:", key: "m", mods: [.cmd]),
            .item("Zoom", action: "performZoom:"),
            .separator,
            .item("Bring All to Front", action: "arrangeInFront:")
        ])),
        .item("Help", submenu: MenuSpec("Help", [
            .item("MixMeister 8 Help", action: "help:", key: "?", mods: [.cmd]),
            .separator,
            .item("Check For Updates...", action: "helpCheckForUpdates:"),
            .separator,
            .item("Support...", action: "helpSupport:")
        ]))
    ])
    static let playlist = MenuSpec("Menu", [
        .item("Cut", action: "cut:", key: "x", mods: [.cmd]),
        .item("Copy", action: "copy:", key: "c", mods: [.cmd]),
        .item("Paste", action: "paste:", key: "v", mods: [.cmd]),
        .separator,
        .item("Delete", action: "del:"),
        .separator,
        .item("Add To Category...", action: "addToCategory:", key: "g", mods: [.ctrl]),
        .item("Find Similar Tracks", action: "findSimilarTracks:", key: "f", mods: [.ctrl]),
        .separator,
        .item("Set As Next Performance Track", action: "setAsNextPerformanceTrack:", key: "n", mods: [.ctrl]),
        .separator,
        .item("Tweaks...", action: "tweaks:", key: "w", mods: [.ctrl]),
        .item("Quick Save Tweak", action: "quickSaveTweak:", key: "s", mods: [.ctrl]),
        .separator,
        .item("Edit Tag...", action: "editTag:", key: "e", mods: [.ctrl]),
        .item("Adjust Track Settings...", action: "adjustTrackSettings:", key: "t", mods: [.ctrl])
    ])
    static let libraryColumns = MenuSpec("Menu", [
        .item("TITLE", action: "toggleTitle:", tag: 1),
        .item("ARTIST", action: "toggleArtist:", tag: 2),
        .item("BPM", action: "toggleBpm:", tag: 3),
        .item("ALBUM", action: "toggleAlbum:", tag: 4),
        .item("TIME", action: "toggleTime:", tag: 5),
        .item("KEY", action: "toggleKey:", tag: 6),
        .item("KEYCODE", action: "toggleKeyCode:", tag: 7),
        .item("TWEAKED", action: "toggleTweaked:", tag: 8),
        .item("YEAR", action: "toggleYear:", tag: 9),
        .item("GENRE", action: "toggleGenre:", tag: 10),
        .item("COMPOSER", action: "toggleComposer:", tag: 11),
        .item("FILENAME", action: "toggleFileName:", tag: 12),
        .item("DATE ADDED", action: "toggleDateAdded:", tag: 13),
        .item("RATING", action: "toggleRating:", tag: 14),
        .item("COMMENTS", action: "toggleComments:", tag: 15),
        .item("TRACK", action: "toggleTrack:", tag: 16),
        .item("BITRATE", action: "toggleBitRate:", tag: 17),
        .item("LABEL", action: "toggleLabel:", tag: 18),
        .item("USER 1", action: "toggleUser1:", tag: 19),
        .item("USER 2", action: "toggleUser2:", tag: 20),
        .item("PLAYLIST", action: "togglePlaylist:", tag: 21)
    ])
    static let playlistColumns = MenuSpec("Menu", [
        .item("#", action: "toggleIndex:"),
        .item("TITLE", action: "toggleTitle:"),
        .item("ARTIST", action: "toggleArtist:"),
        .item("BPM", action: "toggleBpm:"),
        .item("KEY", action: "toggleKey:"),
        .item("KEYCODE", action: "toggleKeyCode:"),
        .item("TRANSITION", action: "toggleTransition:"),
        .item("ALBUM", action: "toggleAlbum:"),
        .item("TIME", action: "toggleTime:"),
        .item("YEAR", action: "toggleYear:"),
        .item("GENRE", action: "toggleGenre:"),
        .item("COMPOSER", action: "toggleComposer:"),
        .item("FILENAME", action: "toggleFileName:"),
        .item("DATE ADDED", action: "toggleDateAdded:"),
        .item("RATING", action: "toggleRating:"),
        .item("COMMENTS", action: "toggleComments:"),
        .item("TRACK", action: "toggleTrack:"),
        .item("BITRATE", action: "toggleBitRate:"),
        .item("LABEL", action: "toggleLabel:"),
        .item("USER 1", action: "toggleUser1:"),
        .item("USER 2", action: "toggleUser2:")
    ])
    static let timelineTrack = MenuSpec("", [
        .item("Cut", action: "cut:", key: "x", mods: [.cmd]),
        .item("Copy", action: "copy:", key: "c", mods: [.cmd]),
        .item("Paste", action: "paste:", key: "v", mods: [.cmd]),
        .separator,
        .item("Delete", action: "del:"),
        .separator,
        .item("Add Volume Marker", action: "addVolumeMarker:", key: "v", mods: []),
        .item("Add Treble Marker", action: "addTrebleMarker:", key: "t", mods: []),
        .item("Add Midrange Marker", action: "addMidrangeMarker:", key: "m", mods: []),
        .item("Add Bass Marker", action: "addBassMarker:", key: "b", mods: []),
        .separator,
        .item("Add Label Marker", action: "addLabelMarker:", key: "l", mods: []),
        .item("Add Effects Parameter Marker", action: "addEffectsParameterMarker:", key: "e", mods: []),
        .separator,
        .item("Add Loop Start Marker", action: "addLoopStartMarker:", key: "9", mods: []),
        .item("Add Loop End Marker", action: "addLoopEndMarker:", key: "0", mods: []),
        .separator,
        .item("Split Segment at Cursor", action: "splitSegmentAtCursor:", key: "s", mods: []),
        .item("Reverse", action: "reverse:"),
        .separator,
        .item("Tweaks...", action: "tweaks:", key: "w", mods: [.ctrl]),
        .item("Adjust Track Settings...", action: "adjustTrackSettings:", key: "t", mods: [.ctrl])
    ])
    static let timelineMarker = MenuSpec("", [
        .item("Edit", action: "markerEdit:"),
        .item("Delete", action: "markerDelete:")
    ])
    static let timelineRange = MenuSpec("Menu", [
        .item("Cut", action: "cut:", key: "x", mods: [.cmd]),
        .item("Copy", action: "copy:", key: "c", mods: [.cmd]),
        .item("Paste", action: "paste:", key: "v", mods: [.cmd]),
        .separator,
        .item("Reverse", action: "reverse:"),
        .separator,
        .item("Delete Volume Markers", action: "deleteVolumeMarkers:"),
        .item("Delete Treble Markers", action: "deleteTrebleMarkers:"),
        .item("Delete Midrange Markers", action: "deleteMidrangeMarkers:"),
        .item("Delete Bass Markers", action: "deleteBassMarkers:"),
        .item("Delete Effects Markers", action: "deleteEffectsMarkers:")
    ])
    static let timelineRuler = MenuSpec("", [
        .item("Add Tempo Marker", action: "rulerAddTempoMarker:"),
        .item("Add Original Tempo Marker", action: "rulerAddOriginalTempoMarker:")
    ])
    static let timelineRulerMarker = MenuSpec("", [
        .item("Edit", action: "editRulerMarkerItem:"),
        .item("Delete", action: "deleteRulerMarkerItem:")
    ])
    static let timelineStrips = MenuSpec("", [
        .item("2 Strips", action: "view2Strips:"),
        .item("4 Strips", action: "view4Strips:"),
        .item("6 Strips", action: "view6Strips:"),
        .item("8 Strips", action: "view8Strips:")
    ])
    static let library = MenuSpec("Menu", [
        .item("Add to End of Playlist", action: "addToEndOfPlaylist:", key: "q", mods: [.ctrl]),
        .separator,
        .item("Delete from Library", action: "deleteFromLibrary:"),
        .separator,
        .item("Preview Song", action: "catPreviewPlay:", key: "\u{d}", mods: []),
        .item("Stop Previewing", action: "catPreviewStop:"),
        .separator,
        .item("Add to Category...", action: "addToCategory:", key: "g", mods: [.ctrl]),
        .item("Remove from Active Category", action: "removeFromActiveCategory:"),
        .item("Find Similar Tracks", action: "findSimilarItems:", key: "f", mods: [.ctrl]),
        .separator,
        .item("Tweaks...", action: "trackPresets:", key: "w", mods: [.ctrl]),
        .separator,
        .item("Edit Tag...", action: "editTag:", key: "e", mods: [.ctrl])
    ])
    static let songSlicer = MenuSpec("Menu", [
        .item("Add Measure Start Marker", action: "addMeasureStartMarker:"),
        .item("Delete All Measure Markers", action: "deleteAllMeasureMarkers:")
    ])
}
