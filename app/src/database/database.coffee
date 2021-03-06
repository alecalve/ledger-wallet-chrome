
ledger.database ?= {}

class ledger.database.Database extends EventEmitter

  constructor: (name, persistenceAdapter) ->
    @_name = name
    @_persistenceAdapter = persistenceAdapter
    @_changes = []

  load: (callback) ->
    @_persistenceAdapter.serialize().then (json) =>
      try
        l "Serialized ", json
        #@_migrateJsonToLoki125 json
        @_db = new loki(@_name, ENV: 'BROWSER')
        if json?
          @_db.loadJSON JSON.stringify(json)
        @_db.save = @scheduleFlush.bind(this)
        for collection in @listCollections()
          collection.setChangesApi on
      catch er
        e er
      callback?()
      @emit 'loaded'
    .fail (er) ->
      e er
    .done()

  addCollection: (collectionName) ->
    collection = @_db.addCollection(collectionName)
    collection.setChangesApi on
    @_persistenceAdapter.declare(collection)
    collection

  listCollections: () -> @_db.collections or []

  getCollection: (collectionName) -> @_db.getCollection(collectionName)

  _migrateJsonToLoki125: (json) ->
    if !json['__version']? or json['__version'] isnt '1.2.5'
      @_migrateDbJsonToLoki125(value) for key, value of json when !key.match(/^(__version)$/)

  _migrateDbJsonToLoki125: (dbJson) ->
    return unless dbJson? and dbJson['collections']?
    for collection in dbJson['collections']
      for item in collection['data']
        item['$loki'] = item['id'] if item['id']
        item['id'] = item['originalId'] or item['$loki']
        delete item['originalId']

  perform: (callback) ->
    if @_db?
      callback?()
    else
      @once 'loaded', callback

  flush: (callback) ->
    changes = @_changes
    @_changes = []
    @perform =>
      clearTimeout @_scheduledFlush if @_scheduledFlush?
      @_persistenceAdapter.saveChanges(changes).then -> callback?()

  scheduleFlush: () ->
    return unless @_db?
    @_changes = @_changes.concat(@_db.generateChangesNotification())
    @_db.clearChanges()
    clearTimeout @_scheduledFlush if @_scheduledFlush?
    if @_changes.length > 50
      @_scheduledFlush = null
      @flush()
    else
      @_scheduledFlush = setTimeout =>
        @_scheduledFlush = null
        @flush()
      , 1000

  isLoaded: () -> if @_db? then yes else no

  getDb:() ->
    throw 'Unable to use database right now (not loaded)' unless @_db?
    @_db

  delete: (callback) ->
    @_persistenceAdapter.delete().then () -> callback?()

  close: () ->
    @flush => @_persistenceAdapter.stop()
    @_db = null

_.extend ledger.database,

  init: (callback) ->
    ledger.database.main = ledger.database.open 'main_' + ledger.storage.databases.name, ledger.storage.databases.getCipher?().key, ->
      callback?()

  open: (databaseName, encryptionKey, callback) ->
    persistenceAdapter = new ledger.database.DatabasePersistenceAdapter(databaseName, encryptionKey)
    db = new ledger.database.Database(databaseName, persistenceAdapter)
    db.load callback
    db

  close: () ->
    ledger.database.main?.close()
    ledger.database.main = null


