$ = (sel) -> document.querySelector sel

allowedImageExt = /\.(png|jpe?g|gif|webp|bmp)$/i

inputItems = ['text', 'color', 'alpha', 'angle', 'space', 'size']
input = {}

imageInput = $ '#image'
graph = $ '#graph'
refresh = $ '#refresh'
autoRefresh = $ '#auto-refresh'
downloadAll = $ '#download-all'
clearAll = $ '#clear-all'
countEl = $ '#count'

items = []

pad2 = (n) -> if n < 10 then '0' + n else '' + n

formatTimestamp = ->
    d = new Date
    '' + d.getFullYear() + '-' + (pad2 d.getMonth() + 1) + '-' + (pad2 d.getDate()) + ' ' + \
        (pad2 d.getHours()) + (pad2 d.getMinutes()) + (pad2 d.getSeconds())

stripExt = (name) ->
    return '' if not name?
    name.replace /\.[^/.]+$/, ''

sanitizeBaseName = (name) ->
    (name or '').replace(/[\\/:*?"<>|]/g, '-').trim()

isSupportedImageFile = (file) ->
    return false if not file?
    return true if file.type? and file.type.indexOf('image/') == 0
    return true if allowedImageExt.test(file.name or '')
    false

dataURItoBlob = (dataURI) ->
    binStr = atob (dataURI.split ',')[1]
    len = binStr.length
    arr = new Uint8Array len

    for i in [0..len - 1]
        arr[i] = binStr.charCodeAt i
    new Blob [arr], type: 'image/png'

canvasToBlob = (canvas) ->
    new Promise (resolve, reject) ->
        if canvas?.toBlob?
            canvas.toBlob ((blob) ->
                if blob? then resolve(blob) else reject new Error 'toBlob failed'
            ), 'image/png'
        else
            try
                resolve dataURItoBlob canvas.toDataURL 'image/png'
            catch err
                reject err

downloadBlob = (blob, filename) ->
    url = URL.createObjectURL blob
    link = document.createElement 'a'
    link.download = filename
    link.href = url
    document.body.appendChild link

    link.click()

    setTimeout ->
        URL.revokeObjectURL url
        document.body.removeChild link
    , 1000

readAsDataURL = (file) ->
    new Promise (resolve, reject) ->
        fileReader = new FileReader
        fileReader.onload = -> resolve fileReader.result
        fileReader.onerror = -> reject fileReader.error or new Error 'FileReader error'
        fileReader.readAsDataURL file

loadImageFromFile = (file) ->
    readAsDataURL(file).then (dataURL) ->
        new Promise (resolve, reject) ->
            img = new Image
            img.onload = -> resolve img
            img.onerror = -> reject new Error '图片加载失败'
            img.src = dataURL

getOptions = ->
    text: (input.text.value or '').trim()
    color: input.color.value
    alpha: parseFloat input.alpha.value
    angle: parseFloat input.angle.value
    space: parseFloat input.space.value
    size: parseFloat input.size.value

makeStyle = (color, alpha) ->
    match = (color or '').match /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i
    return 'rgba(0,0,0,' + alpha + ')' if not match?
    'rgba(' + (parseInt match[1], 16) + ',' + (parseInt match[2], 16) + ',' \
        + (parseInt match[3], 16) + ',' + alpha + ')'

applyWatermark = (item, options) ->
    return if not item?.canvas?
    item.redraw()
    return if not options.text

    canvas = item.canvas
    ctx = item.ctx

    textSize = options.size * Math.max 15, (Math.min canvas.width, canvas.height) / 25

    ctx.save()
    ctx.translate(canvas.width / 2, canvas.height / 2)
    ctx.rotate options.angle * Math.PI / 180

    ctx.fillStyle = makeStyle options.color, options.alpha
    ctx.font = 'bold ' + textSize + 'px -apple-system,"Helvetica Neue",Helvetica,Arial,"PingFang SC","Hiragino Sans GB","WenQuanYi Micro Hei",sans-serif'

    width = (ctx.measureText options.text).width
    step = Math.sqrt (Math.pow canvas.width, 2) + (Math.pow canvas.height, 2)
    margin = (ctx.measureText '啊').width

    x = Math.ceil step / (width + margin)
    y = Math.ceil (step / (options.space * textSize)) / 2

    for i in [-x..x]
        for j in [-y..y]
            ctx.fillText options.text, (width + margin) * i, options.space * textSize * j

    ctx.restore()
    return

applyAll = ->
    options = getOptions()
    items.forEach (item) -> applyWatermark item, options

updateActions = ->
    if countEl?
        if items.length > 0
            countEl.textContent = '已添加 ' + items.length + ' 张图片'
        else
            countEl.textContent = ''

    if downloadAll?
        if items.length > 0 then downloadAll.removeAttribute 'disabled' else downloadAll.setAttribute 'disabled', 'disabled'
    if clearAll?
        if items.length > 0 then clearAll.removeAttribute 'disabled' else clearAll.setAttribute 'disabled', 'disabled'

makeItemName = (file, fallbackBase) ->
    base = sanitizeBaseName stripExt(file?.name) or fallbackBase or 'image'
    base

addImageItem = (img, meta = {}) ->
    canvas = document.createElement 'canvas'
    canvas.width = img.width
    canvas.height = img.height

    ctx = canvas.getContext '2d'
    ctx.drawImage img, 0, 0

    redraw = ->
        ctx.clearRect 0, 0, canvas.width, canvas.height
        ctx.drawImage img, 0, 0

    item =
        id: '' + Date.now() + '-' + Math.random().toString(16).slice(2)
        img: img
        canvas: canvas
        ctx: ctx
        redraw: redraw
        baseName: meta.baseName
        displayName: meta.displayName

    wrapper = document.createElement 'div'
    wrapper.className = 'img-item'

    nameEl = document.createElement 'div'
    nameEl.className = 'img-name'
    nameEl.textContent = item.displayName or item.baseName or '图片'

    wrapper.appendChild nameEl
    wrapper.appendChild canvas
    graph.appendChild wrapper

    canvas.addEventListener 'click', ->
        downloadOne item

    items.push item
    updateActions()
    applyWatermark item, getOptions()
    return

downloadOne = (item, batchStamp = null, index = null) ->
    stamp = batchStamp or formatTimestamp()
    base = item.baseName or 'image'
    suffix = if index? then '-' + (index + 1) else ''
    filename = base + suffix + '-' + stamp + '.png'

    canvasToBlob(item.canvas).then (blob) ->
        downloadBlob blob, filename
    .catch (err) ->
        console.error err
        alert '导出失败，请重试'

addFile = (file, meta = {}) ->
    return if not isSupportedImageFile file

    loadImageFromFile(file).then (img) ->
        baseName = meta.baseName or makeItemName file, 'clipboard'
        displayName = meta.displayName or (file.name or baseName)
        addImageItem img, baseName: baseName, displayName: displayName
    .catch (err) ->
        console.error err
        alert '读取图片失败'

addFiles = (files) ->
    Array.from(files or []).forEach (file) ->
        if isSupportedImageFile file
            addFile file
        else
            alert '仅支持图片文件（png/jpg/gif/webp/bmp 等）'

imageInput?.addEventListener 'change', ->
    addFiles @files
    @value = ''

document.addEventListener 'paste', (e) ->
    data = e.clipboardData
    return if not data?.items?.length

    pasted = []
    for it in data.items when it.kind == 'file'
        f = it.getAsFile()
        pasted.push f if f?

    return if pasted.length == 0
    
    stamp = formatTimestamp()
    for f, idx in pasted
        baseName = 'clipboard'
        displayName = '剪贴板-' + stamp + '-' + (idx + 1)
        addFile f, baseName: baseName, displayName: displayName

autoRefresh?.addEventListener 'change', ->
    if @checked
        refresh.setAttribute 'disabled', 'disabled'
    else
        refresh.removeAttribute 'disabled'

inputItems.forEach (item) ->
    el = $ '#' + item
    input[item] = el
    el.addEventListener 'input', ->
        applyAll() if autoRefresh.checked

refresh?.addEventListener 'click', applyAll

downloadAll?.addEventListener 'click', ->
    return if items.length == 0
    stamp = formatTimestamp()

    downloadNext = (idx) ->
        return if idx >= items.length
        downloadOne(items[idx], stamp, idx).then (->
            setTimeout (-> downloadNext idx + 1), 200
        ).catch (->
            setTimeout (-> downloadNext idx + 1), 200
        )

    downloadNext 0

clearAll?.addEventListener 'click', ->
    items.length = 0
    graph.innerHTML = ''
    updateActions()

updateActions()
