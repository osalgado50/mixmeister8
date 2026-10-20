# Inventario de interfaz (nibs de MixMeister Studio 7.8)

Generado con `rea decode-interface-builder`. Solo datos de recursos: títulos, textos, menús, selectores de acción y clases propias referenciadas.

## AddCategoryDlg.nib
**Ventanas:** Add Category to Catalog
**Clases propias:** AddCategoryController, MmMainWindow
**Textos:** Category Name: · OK · Cancel
**Acciones:** cancel:, ok:
**Outlets:** categoryText, initialFirstResponder, o_addCategoryDlg

## AddMusicFilesToLibraryDlg.nib
**Ventanas:** Add Music Files To The Library
**Clases propias:** MmMainWindow
**Textos:** OK · Add files and/or folders... · Automatically add files by monitoring folders... · Add a single file... · Box · MixMeister supports these music file formats:
      AIFC, AIFF, AIF
      M4A, MP3, WAV · Cancel
**Acciones:** cancel:, ok:
**Outlets:** initialFirstResponder, o_addMusicFilesDlg, radioMatrix

## AddToCategoryDlg.nib
**Ventanas:** Add to Category
**Clases propias:** AddToCategoryController, CategoryDataSource, MmMainWindow
**Textos:** Category Name · 9 · OK · Cancel · New...
**Acciones:** cancel:, newCategory:, ok:
**Outlets:** dataSource, o_addToCategoryController, o_addToCategoryDlg, o_tableColumn

## BuyNowDlg.nib
**Ventanas:** Panel
**Clases propias:** BuyNowController, MmMainWindow
**Textos:** Button
**Acciones:** buyFullVersion, continue, downloadOtherProduct
**Outlets:** o_buyNowDlg, o_buyNowImage

## CdBurnerDlg.nib
**Ventanas:** Panel
**Clases propias:** PlaylistController
**Textos:** Automatically split into tracks · Split into tracks at Label Markers · Radio · Layout Options: · Cancel · Continue
**Acciones:** doCancelButtonProc:, doContinueButtonProc:, doLayoutRadioProc:
**Outlets:** o_BurnLayoutDlg

## DeleteCategoryDlg.nib
**Ventanas:** Delete Category
**Clases propias:** CategoryDataSource, DeleteCategoryController, IdBstrItemFormatter, MmMainWindow
**Textos:** Cancel · OK · Category to Delete:
**Acciones:** cancel:, ok:
**Outlets:** dataSource, formatter, o_categoryCombo, o_deleteCategoryDlg

## DeleteLibraryFile.nib
**Ventanas:** Panel
**Clases propias:** DeleteLibraryFile
**Textos:** Change the Library and leave the file. · Change the Library and delete the file · Radio · You are about to delete one or more more items from the Library. · Cancel · Continue · How would you like to proceed? · This option simply removes the song from MixMeister's library. The music file remains on your hard disk. · This option will remove the song from MixMeister's library and delete the music file from your hard disk.
**Acciones:** doCancelButtonProc, doContinueButtonProc
**Outlets:** o_panelObject, o_radioButtons

## EditTagDlg.nib
**Ventanas:** Edit Tag
**Clases propias:** EditTagController, MmMainWindow
**Menús:** minor | ## OtherViews | major | ## OtherViews | none | 1A | 2A | C | ## OtherViews | none | C#
**Textos:** Auto Detect · File Name · Beats Per Minute (BPM) · Number of Beats in Music File · Radio · Composer: · Album: · Rating: · Artist: · Genre: · Comments: · Title: · Year: · Label: · User 1: · User 2: · Box · Tap · 1/2x · 2x · Key: · Key Code: · Date Added: · Bitrate: · Tweaks: · System Font Text · Time: · Track Number: · OK · Cancel · Preview · Stop · Fast Forward
**Acciones:** autoDetect:, beatOrBpm:, bpmEdit:, cancel:, doubleBpm:, fastForward:, halfBpm:, keyChange:, keyCodeChange:, keyTypeChange:, ok:, preview:, stop:, takeIntValueFrom:, tap:
**Outlets:** _album, _artist, _autoDetect, _beatStepper, _beats, _bitrate, _bpm, _bpmOrBeats, _comments, _composer, _dateAdded, _doubleBpm, _fileName, _genre, _halfBpm, _key, _keyCode, _keyType, _label, _rating, _tap, _time, _title, _trackNumber, _tweaks, _user1, _user2, _year, initialFirstResponder, nextKeyView, o_editTagController, o_editTagDlg

## FileOrDeviceDlg.nib
**Ventanas:** Panel
**Clases propias:** PlaylistController
**Textos:** Export my playlist to one or more files · Export my playlist to iTunes · Radio · What would you like to do? · Cancel · Continue
**Acciones:** doCancelButton:, doOkButton:, doOptionsRadioButton:
**Outlets:** o_FileOrDeviceDlg

## FindFileErrorDlg.nib
**Ventanas:** Unable to Find File
**Clases propias:** FindFileErrorController, MmMainWindow
**Textos:** Skip this file · Specify a new location for the file · Radio · Do this again next time · filename · Cancel · OK · MixMeister cannot locate the following music file: · This file may have been moved or deleted.  If the file is located on a network, it may not be currently available. · What would you like to do?
**Acciones:** cancel:, ok:
**Outlets:** o_doThisAgain, o_fileName, o_findFileErrorController, o_findFileErrorDlg, o_whatToDo

## ImportITunesDlg.nib
**Ventanas:** Import from iTunes
**Clases propias:** MmMainWindow
**Menús:** ## OtherViews
**Textos:** Cancel · MixMeister can import all or some of the music from your iTunes database. · Import all iTunes music · Import songs from an iTunes playlist · Radio · Import · Create categories for iTunes playlists
**Acciones:** cancel:, matrixChanged:, ok:
**Outlets:** createCategoriesButton, o_importITunesDlg, playlistsButton, radioMatrix

## MainMenu.nib/keyedobjects-101300.nib
**Acciones:** addBassMarker:, addEffectsParameterMarker:, addFilesToLibrary:, addLabelMarker:, addLoopEndMarker:, addLoopStartMarker:, addMeasureStartMarker:, addMidrangeMarker:, addToCategory:, addToEndOfPlaylist:, addTrebleMarker:, addVolumeMarker:, adjustTrackSettings:, appendPlayList:, arrangeInFront:, burnCD:, catPreviewPlay:, catPreviewStop:, cleanUpLibrary:, clearRecentFiles:, copy:, cut:, del:, delete:, deleteAllMeasureMarkers:, deleteBassMarkers:, deleteCategory:, deleteEffectsMarkers:, deleteFromLibrary:, deleteMidrangeMarkers:, deleteRulerMarkerItem:, deleteTrebleMarkers:, deleteVolumeMarkers:, doAudioSetupDialog:, dragTempo:, editRulerMarkerItem:, editTag:, exportLibrary:, exportPlaylistAsMobileMix:, exportPlaylistToDevice:, exportPlaylistToFile:, findSimilarItems:, findSimilarTracks:, handleMenuItem:, help:, helpBuyNow:, helpCheckForUpdates:, helpRegisterOnline:, helpSupport:, hide:, hideOtherApplications:, importITunes:, importLibrary:, jogBackward:, jogForward:, markerDelete:, markerEdit:, mixNow:, mixPerformanceNow:, newCategory:, newPlayList:, nextTrack:, openPlayList:, orderFrontStandardAboutPanel:, paste:, performMiniaturize:, performPause:, performZoom:, playPause:, preferences:, previousTrack:, printLibrary:, printPlaylist:, pushTempo:, quickSaveTweak:, redo:, removeFromActiveCategory:, resetPerformancePosition:, reverse:, rulerAddOriginalTempoMarker:, rulerAddTempoMarker:, savePlayList:, savePlayListAs:, searchTextDidChange:, selectAll:, setAsNextPerformanceTrack:, showPerformedTracks:, smartPlaylist:, snapTo1Measure:, snapTo2Measures:, snapTo4Measures:, snapTo8Measures:, snapToBeat:, snapToEighthNote:, snapToHalfNote:, snapToQuarterNote:, snapToSixteenthNote:, splitSegmentAtCursor:, stop:, stopAndCueNext:, terminate:, timelineRulerMeasuresAndBeats:, timelineRulerTime:, toggleAlbum:, toggleArtist:, toggleBitRate:, toggleBpm:, toggleComments:, toggleComposer:, toggleDateAdded:, toggleFileName:, toggleGenre:, toggleIndex:, toggleKey:, toggleKeyCode:, toggleLabel:, togglePlaylist:, toggleRating:, toggleTime:, toggleTitle:, toggleTrack:, toggleTransition:, toggleTweaked:, toggleUser1:, toggleUser2:, toggleYear:, trackPresets:, tweaks:, undo:, unhideAllApplications:, view2Strips:, view4Strips:, view6Strips:, view8Strips:, viewEffects:, viewEffectsRack:, viewLibrary:, viewSongSlicer:, zoomIn:, zoomOut:
**Outlets:** 

## MainMenu.nib/keyedobjects-110000.nib
**Acciones:** addBassMarker:, addEffectsParameterMarker:, addFilesToLibrary:, addLabelMarker:, addLoopEndMarker:, addLoopStartMarker:, addMeasureStartMarker:, addMidrangeMarker:, addToCategory:, addToEndOfPlaylist:, addTrebleMarker:, addVolumeMarker:, adjustTrackSettings:, appendPlayList:, arrangeInFront:, burnCD:, catPreviewPlay:, catPreviewStop:, cleanUpLibrary:, clearRecentFiles:, copy:, cut:, del:, delete:, deleteAllMeasureMarkers:, deleteBassMarkers:, deleteCategory:, deleteEffectsMarkers:, deleteFromLibrary:, deleteMidrangeMarkers:, deleteRulerMarkerItem:, deleteTrebleMarkers:, deleteVolumeMarkers:, doAudioSetupDialog:, dragTempo:, editRulerMarkerItem:, editTag:, exportLibrary:, exportPlaylistAsMobileMix:, exportPlaylistToDevice:, exportPlaylistToFile:, findSimilarItems:, findSimilarTracks:, handleMenuItem:, help:, helpBuyNow:, helpCheckForUpdates:, helpRegisterOnline:, helpSupport:, hide:, hideOtherApplications:, importITunes:, importLibrary:, jogBackward:, jogForward:, markerDelete:, markerEdit:, mixNow:, mixPerformanceNow:, newCategory:, newPlayList:, nextTrack:, openPlayList:, orderFrontStandardAboutPanel:, paste:, performMiniaturize:, performPause:, performZoom:, playPause:, preferences:, previousTrack:, printLibrary:, printPlaylist:, pushTempo:, quickSaveTweak:, redo:, removeFromActiveCategory:, resetPerformancePosition:, reverse:, rulerAddOriginalTempoMarker:, rulerAddTempoMarker:, savePlayList:, savePlayListAs:, searchTextDidChange:, selectAll:, setAsNextPerformanceTrack:, showPerformedTracks:, smartPlaylist:, snapTo1Measure:, snapTo2Measures:, snapTo4Measures:, snapTo8Measures:, snapToBeat:, snapToEighthNote:, snapToHalfNote:, snapToQuarterNote:, snapToSixteenthNote:, splitSegmentAtCursor:, stop:, stopAndCueNext:, terminate:, timelineRulerMeasuresAndBeats:, timelineRulerTime:, toggleAlbum:, toggleArtist:, toggleBitRate:, toggleBpm:, toggleComments:, toggleComposer:, toggleDateAdded:, toggleFileName:, toggleGenre:, toggleIndex:, toggleKey:, toggleKeyCode:, toggleLabel:, togglePlaylist:, toggleRating:, toggleTime:, toggleTitle:, toggleTrack:, toggleTransition:, toggleTweaked:, toggleUser1:, toggleUser2:, toggleYear:, trackPresets:, tweaks:, undo:, unhideAllApplications:, view2Strips:, view4Strips:, view6Strips:, view8Strips:, viewEffects:, viewEffectsRack:, viewLibrary:, viewSongSlicer:, zoomIn:, zoomOut:
**Outlets:** 

## MainMenu.nib/keyedobjects.nib
**Ventanas:** MixMeister · Window
**Clases propias:** CatalogDataSource, CategoryComboDataSource, IdBstrItemFormatter, LibraryController, MmCornerView, MmEffectsList, MmEffectsListController, MmEffectsRackView, MmEfxCtrl, MmLibrary, MmMainDelegate, MmPlaylist, MmSongSlicer, MmSplitView, MmSplitViewDelegate, MmSplitViewDelegateNoCollapse, MmSplitViewDelegateNoCollapseHorz, MmTableView, MmTimeline, MmTimelineCtrlView, MmToolbar, MmTrackCtrlView, OutputConfigurationDlg, PlaylistController, PlaylistDataSource, TimelineController
**Menús:** Item1 | ## OtherViews | Item2 | Item3 | ## File | Add Files To Library... | New Playlist [n] | Open Playlist... [o] | Append Playlist... | Open Recent Playlist | ## Open Recent Playlist | Clear Menu | Save Playlist [s] | Save Playlist As… [S] | Export Playlist to File... | Export Playlist to iTunes... | Export Playlist as Mobile Mix... | Burn CD... | Print Library… | Print Playlist… [p] | ## View | Library | Effects | Song Slicer | Effects Rack | Zoom In [+] | Zoom Out [-] | Timeline Ruler | ## Timeline Ruler | Time | Measures and Beats | 2 Strips | 4 Strips | 6 Strips | 8 Strips | Show Performed Tracks [R] | ## Help | MixMeister Fusion Help [?] | Buy Now... | Register Online... | Check For Updates... | Support... | ## Menu | Cut [x] | Copy [c] | Paste [v] | Delete | Add To Category... [g] | Find Similar Tracks [f] | Set As Next Performance Track [n] | Tweaks... [w] | Quick Save Tweak [s] | Edit Tag... [e] | Adjust Track Settings... [t] | ## Columns | TITLE | ARTIST | BPM | ALBUM | TIME | KEY | KEYCODE | TWEAKED | YEAR | GENRE | COMPOSER | FILENAME | DATE ADDED | RATING | COMMENTS | TRACK | BITRATE | LABEL | USER 1 | USER 2 | PLAYLIST | ## Transitions | Item | ## Menu | TITLE | ARTIST | BPM | ALBUM | TIME | KEY | KEYCODE | TWEAKED | YEAR | GENRE | COMPOSER | FILENAME | DATE ADDED | RATING | COMMENTS | TRACK | BITRATE | LABEL | USER 1 | USER 2 | PLAYLIST | ## Menu | # | TITLE | ARTIST | BPM | KEY | KEYCODE | TRANSITION | ALBUM | TIME | YEAR | GENRE | COMPOSER | FILENAME | DATE ADDED | RATING | COMMENTS | TRACK | BITRATE | LABEL | USER 1 | USER 2 | Cut [x] | Copy [c] | Paste [v] | Delete | Add Volume Marker [v] | Add Treble Marker [t] | Add Midrange Marker [m] | Add Bass Marker [b] | Add Label Marker [l] | Add Effects Parameter Marker [e] | Add Loop Start Marker [9] | Add Loop End Marker [0] | Split Segment at Cursor [s] | Reverse | Tweaks... [w] | Adjust Track Settings... [t] | Edit | Delete | ## Menu | Cut [x] | Copy [c] | Paste [v] | Reverse | Delete Volume Markers | Delete Treble Markers | Delete Midrange Markers | Delete Bass Markers | Delete Effects Markers | Add Tempo Marker | Add Original Tempo Marker | Edit | Delete | 2 Strips | 4 Strips | 6 Strips | 8 Strips | ## Menu | Add to End of Playlist [q] | Delete from Library | Preview Song [] | Stop Previewing | Add to Category... [g] | Remove from Active Category | Find Similar Tracks [f] | Tweaks... [w] | Edit Tag... [e] | ## Menu | NSSearchFieldRecentsMenuItemTag | No Recent Searches |   | Clear | ## Menu | Add Measure Start Marker | Delete All Measure Markers | Bring All to Front | ## Window | Minimize [m] | About MixMeister | ## MixMeister | Preferences… [,] | Hide MixMeister [h] | Quit MixMeister [q] | Hide Others [h] | Show All | Copy [c] | ## Edit | Undo [z] | Cut [x] | Delete | Paste [v] | Select All [a] | Redo [Z] | Zoom | New Category... | ## Library | Delete Category... | Clean Up Library... | Import Library... | Export Library... | Play/Pause | ## Playback | Stop | Jog Forward | Jog Backward | Mix Now [] | Previous Track | Next Track | Reset Performance Position [r] | Drag Tempo [[] | Mix Performance Now [] | Fade and Cue Next [] | Push Tempo []] | Perform/Pause [] | Snap To Beat [B] | ## Tools | Audio Output Configuration... | 8 Measures | ## Snap To | Add To Category... [g] | Remove From Active Category... | Find Similar Tracks [f] | Add Bass Marker [b] | Add Volume Marker [v] | Add Treble Marker [t] | Add Midrange Marker [m] | Add Label Marker [l] | Add Effects Parameter Marker [e] | Add Loop Start Marker [9] | Add Loop End Marker [0] | Split Segment at Cursor [s] | Reverse | Set As Next Performance Track [n] | 4 Measures | Sixteenth Note | 2 Measures | Eighth Note | 1 Measure | Half Note | Quarter Note | Quick Save Tweak [s] | Tweaks... [w] | Edit Tag... [e] | Adjust Track Settings... [t] | Import from iTunes... | Smart Playlist... | ## MainMenu | MixMeister | Services | ## Services | File | Edit | View | Library | Columns | Playback | Tools | Transitions | Snap To | Window | Help
**Textos:** # · TITLE · ARTIST · BPM · KEY · KEYCODE · TRANSITION · ALBUM · TIME · YEAR · GENRE · COMPOSER · FILENAME · DATE ADDED · RATING · COMMENTS · TRACK · BITRATE · LABEL · USER 1 · USER 2 · Copy music files to the same folder · Item1 · File Format: · TWEAKED · PLAYLIST · Effect · SEARCH LIBRARY · search · 7.1.2 · Version
**Acciones:** addBassMarker:, addEffectsParameterMarker:, addFilesToLibrary:, addLabelMarker:, addLoopEndMarker:, addLoopStartMarker:, addMeasureStartMarker:, addMidrangeMarker:, addToCategory:, addToEndOfPlaylist:, addTrebleMarker:, addVolumeMarker:, adjustTrackSettings:, appendPlayList:, arrangeInFront:, burnCD:, catPreviewPlay:, catPreviewStop:, cleanUpLibrary:, clearRecentFiles:, copy:, cut:, del:, delete:, deleteAllMeasureMarkers:, deleteBassMarkers:, deleteCategory:, deleteEffectsMarkers:, deleteFromLibrary:, deleteMidrangeMarkers:, deleteRulerMarkerItem:, deleteTrebleMarkers:, deleteVolumeMarkers:, doAudioSetupDialog:, dragTempo:, editRulerMarkerItem:, editTag:, exportLibrary:, exportPlaylistAsMobileMix:, exportPlaylistToDevice:, exportPlaylistToFile:, findSimilarItems:, findSimilarTracks:, handleMenuItem:, help:, helpBuyNow:, helpCheckForUpdates:, helpRegisterOnline:, helpSupport:, hide:, hideOtherApplications:, importITunes:, importLibrary:, jogBackward:, jogForward:, markerDelete:, markerEdit:, mixNow:, mixPerformanceNow:, newCategory:, newPlayList:, nextTrack:, openPlayList:, orderFrontStandardAboutPanel:, paste:, performMiniaturize:, performPause:, performZoom:, playPause:, preferences:, previousTrack:, printLibrary:, printPlaylist:, pushTempo:, quickSaveTweak:, redo:, removeFromActiveCategory:, resetPerformancePosition:, reverse:, rulerAddOriginalTempoMarker:, rulerAddTempoMarker:, savePlayList:, savePlayListAs:, searchTextDidChange:, selectAll:, setAsNextPerformanceTrack:, showPerformedTracks:, smartPlaylist:, snapTo1Measure:, snapTo2Measures:, snapTo4Measures:, snapTo8Measures:, snapToBeat:, snapToEighthNote:, snapToHalfNote:, snapToQuarterNote:, snapToSixteenthNote:, splitSegmentAtCursor:, stop:, stopAndCueNext:, terminate:, timelineRulerMeasuresAndBeats:, timelineRulerTime:, toggleAlbum:, toggleArtist:, toggleBitRate:, toggleBpm:, toggleComments:, toggleComposer:, toggleDateAdded:, toggleFileName:, toggleGenre:, toggleIndex:, toggleKey:, toggleKeyCode:, toggleLabel:, togglePlaylist:, toggleRating:, toggleTime:, toggleTitle:, toggleTrack:, toggleTransition:, toggleTweaked:, toggleUser1:, toggleUser2:, toggleYear:, trackPresets:, tweaks:, undo:, unhideAllApplications:, view2Strips:, view4Strips:, view6Strips:, view8Strips:, viewEffects:, viewEffectsRack:, viewLibrary:, viewSongSlicer:, zoomIn:, zoomOut:
**Outlets:** cornerView, dataSource, delegate, initialFirstResponder, m_playlistController, menu, o_ControlsView, o_CopyAuidoCheckBox, o_FormatPopup, o_FormatView, o_catalogTableView, o_categoryDataSource, o_columnMenu, o_contextMenuForKeyboard, o_effectsList, o_effectsListController, o_effectsListView, o_effectsRackView, o_fileMenu, o_libEffectsTab, o_libraryController, o_libraryView, o_mainWindow, o_minimizeToolbar, o_overlayToolBar, o_paneSelectToolbar, o_playListView, o_playlistController, o_playlistTableView, o_rackSlicerTab, o_recentFilesMenu, o_scrollView, o_searchField, o_songSlicer, o_songSlicerView, o_splashImage, o_splashScreen, o_splashVersionText, o_tableView, o_tbEfxMod, o_tbMinimize, o_timeline, o_timelineContextMenu, o_timelineController, o_timelineCtrlView, o_timelineMarkerContextMenu, o_timelineRangeContextMenu, o_timelineRulerContextMenu, o_timelineRulerMarkerContextMenu, o_timelineStripsContextMenu, o_toolBar, o_toolbar00, o_toolbar01, o_toolbar10, o_toolbar11, o_trackCtrlView, o_vertSplitView, o_viewMenu, searchMenuTemplate

## MusicFileNoAccessDlg.nib
**Ventanas:** Unable to modify files
**Clases propias:** MmMainDelegate, MusicFileNoAccessController
**Textos:** Don't try to update these files again. · Retry · OK · MixMeister is unable to update the following music files: · These files may be inaccessible because they are open in another application or they may be set to read-only.
**Acciones:** ok:, retry:
**Outlets:** dataSource, o_dontTryAgain, o_fileList, o_musicFilesNoAccessController, o_musicFilesNoAccessDlg

## OutputConfigurationDlg.nib
**Ventanas:** Audio Output Configuration
**Clases propias:** OutputConfigurationDlg
**Menús:** Item1 | ## OtherViews | Item2 | Item3 | Item1 | ## OtherViews | Item2 | Item3 | Item1 | ## OtherViews | Item2 | Item3
**Textos:** Reliable Playback · Responsive Playback · Output Delay · CoreAudio · ASIO · Radio · Output Interface · Cancel · OK · Single Output: · Dual Output: · Output Mode · Main and Previw output: · Main output (speakers) · Preview output (headphones) · Advanced Settings
**Acciones:** doCancelButton:, doDelaySlider:, doDisclosureToggle:, doDualMainPopup:, doDualPreviewPopup:, doInterfaceRadio:, doModeRadio:, doOkButton:, doSinglePopup:
**Outlets:** audioSetupPanel, oDelaySlider, oDualMainPopup, oDualPreviewPopup, oInterfaceRadio, oModeRadio, oSinglePopup, o_AdvancedDisclosureButton, o_AdvancedView, o_StandardView

## Preferences.nib
**Ventanas:** MixMeister Preferences · MIDI Configuration
**Clases propias:** IdBstrItemFormatter, MIDIConfigurationController, MmMainWindow, PrefLibraryController, PrefMidiController, PrefMusicFilesController, PrefPlaylistController, PrefPlotFilesController, PreferencesController
**Menús:** ## OtherViews | ## OtherViews | ## OtherViews
**Textos:** Hardware Control: · Control Template: · Customize · Midi Clock Output: · Update music files on my hard drive with Library settings · Keep the file on my hard drive (Just delete it from the Library) · Delete the file from my hard drive · Ask me what to do · Radio · When deleting music files from the Library: · Automatically update the library based on the following directories: · Add Directory... · Remove · Automatically Build Categories Based on Directory Structure · Text Cell · After creating a plot file for each song, MixMeister stores the plot file for later use.  This saves time when you load a track.  You can change the directory where the plot files are stored. · Plot File Directory: · Browse · Store plot files with music files · Restore Defaults · When adding tracks to the playlist, use this transition: · Automatic (play tracks at their original tempo) · Manual (play a group of beat mixed tracks at the same tempo by default) · Tempo control for beat mixed tracks... · OK · Cancel · Apply · Learn
**Acciones:** addDirectory:, apply:, autoBuildCategories:, autoUpdateLibrary:, browse:, cancel:, customize:, directorySelected:, learn:, ok:, removeDirectory:, restoreDefaults:, selectControlTemplate:, selectHardwareControl:, selectMidiClockOutput:, selectionChanged:, somethingChanged:, storePlotFilesWithMusic:
**Outlets:** dataSource, formatter, o_apply, o_autoBuildCategories, o_autoUpdateLibrary, o_browse, o_controlTemplate, o_deletingMusicFiles, o_directories, o_hardwareControl, o_learn, o_midiClockOutput, o_midiCustomizeDlg, o_plotFileDirectory, o_prefLibraryController, o_prefMidiController, o_prefMusicFilesController, o_prefPlaylistController, o_prefPlotFilesController, o_preferencesController, o_preferencesDlg, o_removeDirectory, o_storePlotFilesWithMusic, o_tableView, o_tempoControl, o_transition, o_updateMusicFiles

## ProgressStatus.nib
**Ventanas:** Status
**Clases propias:** MmMainWindow, ProgressController
**Textos:** Cancel
**Acciones:** cancel:
**Outlets:** actionText, o_progressController, o_progressDlg, progressIndicator

## RegistrationDlg.nib
**Ventanas:** MixMeister Product Registration
**Clases propias:** MmMainWindow, RegistrationController
**Textos:** MixMeister Product Registration · Welcome to MixMeister. · Please enter your license key: · OK · Cancel
**Acciones:** cancel, ok
**Outlets:** o_registrationDlg, o_registrationKey

## SavePlaylistAudio.nib
**Clases propias:** SavePlaylistAudioController
**Menús:** Item1 | ## OtherViews | Item2 | Item3 | Item1 | ## OtherViews | Item2 | Item3
**Textos:** Save as type: · Format: · Estimated Disk Space Required: · Each song · Each track using label markers · Radio · Create separate files for:
**Acciones:** changeFileType:, changeFormatPopup:, toggleSplitCheckBox:
**Outlets:** o_AccessoryView, o_DataFormat, o_FileType, o_SizeTextField, o_SplitCheckBox, o_SplitRadioButton

## SaveToDevice.nib
**Ventanas:** Save Playlist to Device
**Clases propias:** SaveToDeviceController
**Textos:** Name your mix for iTunes: · Artist: · Title: · Cancel · Save
**Acciones:** doCancelButton, doSaveButton
**Outlets:** o_artistText, o_dialogPanel, o_saveButton, o_titleText

## SmartPlaylist.nib
**Ventanas:** Create Smart Playlist
**Clases propias:** CategoryComboDataSource, IdBstrItemFormatter, MmMainWindow
**Textos:** 25 · 100 · 140 · is · to · Select from category · Within BPM range · Where · Limit to · tracks · Cancel · Create · Automatically create a Playlist from the Library which contains the following tracks:
**Acciones:** cancel:, ok:, takeIntValueFrom:, takeIntegerValueFrom:
**Outlets:** bpmHighTextField, bpmLowTextField, bpmRangeCheckBox, categoryCheckBox, categoryComboBox, dataSource, formatter, limitCheckBox, limitTextField, o_smartPlaylistDlg, whereCheckBox, whereComboBox, whereTextField

## StudioOutputConfigurationDlg.nib
**Ventanas:** Audio Output Configuration
**Clases propias:** OutputConfigurationDlg
**Menús:** Item1 | ## OtherViews | Item2 | Item3
**Textos:** Cancel · CoreAudio · ASIO · Radio · OK · Reliable Playback · Responsive Playback · Output Delay · Output Interface · Main output: · Output Mode · Advanced Settings
**Acciones:** doCancelButton, doDelaySlider, doDisclosureToggle, doInterfaceRadio, doOkButton, doSinglePopup
**Outlets:** audioSetupPanel, oDelaySlider, oInterfaceRadio, oSinglePopup, o_AdvancedDisclosureButton, o_AdvancedView, o_StandardView

## TrackSettings.nib
**Ventanas:** Track Settings
**Clases propias:** AdjustTrackSettingsController, MmMainWindow
**Textos:** Primary Track · Overlay Track · Radio · OK · Cancel · System Font Text · Automatic · Beat Slicer · Beat sync with Master Tempo (Overlays only) · Track Style · semitones · Key Adjustment: · Blend Beats Using: · Slice Size:
**Acciones:** blendChanged:, cancel:, keyStep:, keyTextChanged:, ok:, styleChanged:
**Outlets:** initialFirstResponder, o_adjustTrackSettingsController, o_adjustTrackSettingsDlg, o_beatSync, o_blendBeatsUsing, o_keyAdjustment, o_semitoneStepper, o_sliceSize, o_title, o_trackStyle

## TweaksDlg.nib
**Ventanas:** Tweaks · Save Tweak As...
**Clases propias:** MmMainWindow, TweaksController
**Textos:** System Font Text · OK · Cancel · (L)oad · (S)ave · Save (A)s... · (R)ename · (Del)ete · Set As (D)efault · Tweak Name:
**Acciones:** cancel:, del:, load:, ok:, rename:, save:, saveAs:, saveAsCancel:, saveAsOK:, setAsDefault:
**Outlets:** initialFirstResponder, o_deleteButton, o_loadButton, o_renameButton, o_saveAsButton, o_saveAsName, o_saveAsPanel, o_saveButton, o_setAsDefaultButton, o_tableView, o_title, o_trackPresetsController, o_trackPresetsDlg

## UpdateFoundDlg.nib
**Ventanas:** MixMeister Product Updates
**Clases propias:** MmMainWindow, UpdateFoundController
**Textos:** Exit MixMeister and visit the download page · Get a reminder one week from now · Turn off the automatic check for updates · Radio · Cancel · OK · A new version of this software is available. · How would you like to proceed? · You can always check for updates manually by clicking "Check for Updates"in the help menu.
**Acciones:** cancel, ok
**Outlets:** o_matrix, o_updateFoundController, o_updateFoundDlg

## WaitForAudioDevice.nib
**Ventanas:** Panel
**Clases propias:** WaitForAudioDevice
**Textos:** Please wait while your selected audio device(s) are initialized...
**Outlets:** o_panelObject

## WaitForITunesDlg.nib
**Ventanas:** Panel
**Clases propias:** iTunesController
**Textos:** Please wait while iTunes prepares the file...
**Outlets:** o_dialogPanel, o_progressBar

## WebView.nib
**Ventanas:** MixMeister
**Clases propias:** MmMainWindow
**Outlets:** o_webView
