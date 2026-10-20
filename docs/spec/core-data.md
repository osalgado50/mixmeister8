# Modelo Core Data del original (MmCatalog.mom)

Decodificado con `tools/mom.py`. Tipos según NSAttributeType.


### TrackPreset  (clase: TrackPresetMO)
- trackPresetData: Binary
- lastUpdated: Date
- smallFingerprint: Binary
- profileWorkItem: -> ProfileWorkItem (a-muchos)
- syncRequired: Int32
- trackPresetID: Int32 (obligatorio)
- trackPresetName: String
- trackPresetGlobalID: String
- catalog: -> Catalog (a-uno)

### Category  (clase: CategoryMO)
- lastUpdated: Date
- categoryGlobalID: String
- catalog: -> Catalog (a-muchos)
- categoryName: String
- categoryID: Int32

### Catalog  (clase: CatalogItemMO)
- pendingDefaultMixClear: Int32
- profileWorkItem: -> ProfileWorkItem (a-muchos)
- catalogGlobalID: String
- category: -> Category (a-muchos)
- beatCount: Int32
- genre: String
- comments: String
- sampleRate: Int32
- label: String
- albumName: String
- year: String
- key: Int32
- keyFlags: Int32
- musicFileID: String
- lastUpdated: Date
- fileType: Int32
- user1: String
- trackNumber: Int32
- songTitle: String
- bpm: Float
- fileName: String
- fileLastWritten: Date
- catalogID: Int32
- artistName: String
- composer: String
- pendingUpdate: Int32
- bitRate: Int32
- sampleCount: Int64
- dateAdded: Date
- trackPreset: -> TrackPreset (a-muchos)
- user2: String
- thumbNail: Binary
- montagePreset: -> MontagePreset (a-muchos)
- defaultTrackPreset: -> TrackPreset (a-uno)
- rating: Int32

### MontagePreset  (clase: $null)
- flags: Int32
- catalog: -> Catalog (a-muchos)
- transitionLength: Float
- name: String
- styleID: Int32
- transitionID: Int32

### ProfileWorkItem  (clase: ProfileWorkItemMO)
- trackPreset: -> TrackPreset (a-uno)
- catalog: -> Catalog (a-uno)
- workItemID: Int32 (obligatorio)
- priority: Int32
- checkoutExpirationDate: Date
- action: String
