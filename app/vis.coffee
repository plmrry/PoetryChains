window.THREE = require("three")
createGeometry = require('three-bmfont-text')
Shader = require "./shaders/sdf"
xtend = require 'xtend'
createOrbitViewer = require('three-orbit-viewer')(THREE)
assert = require "assert"

module.exports = class Main
  SCALE_TEXT = 0.005

  SPEED_MULTIPLIER = 0.5

  CAMERA_PAN_DURATION = 2000 * SPEED_MULTIPLIER
  FADE_DURATION = 3000 * SPEED_MULTIPLIER
  # CHAIN_FADE_DELAY = 5000 * SPEED_MULTIPLIER

  CAMERA_Z = -9

  scaleText: SCALE_TEXT
  speedMultiplier: SPEED_MULTIPLIER

  constructor: ->
    console.log "Starting Vis"

    @renderer = new THREE.WebGLRenderer()
    @renderer.setPixelRatio( window.devicePixelRatio )
    @renderer.setSize( window.innerWidth, window.innerHeight )
    @renderer.setClearColor( "rgb(255, 255, 255)" )

    document.body.appendChild( @renderer.domElement )

    @scene = new THREE.Scene()

    fov = 70
    aspect = window.innerWidth / window.innerHeight
    [ near, far ] = [ 0.1, 1000 ]
    @camera = new THREE.PerspectiveCamera( fov, aspect, near, far )

    [_x, _y, _z] = [0, 0, CAMERA_Z]
    @camera.position.z = _z
    @camera.position.x = _x
    @camera.position.y = _y
    @camera.lookAt new THREE.Vector3(_x,_y,0)

    onWindowResize = =>
      @camera.aspect = window.innerWidth / window.innerHeight
      @camera.updateProjectionMatrix()
      @renderer.setSize( window.innerWidth, window.innerHeight )

    window.addEventListener( 'resize', onWindowResize, false )

    do animate = =>
      requestAnimationFrame animate
      @renderer.render @scene, @camera

  addChain: (text) =>
    chainVis = new ChainVis @scene, @camera, @font, @texture
    chainVis.start text

  addNetwork: (network) =>
    colocationVis = new ColocationVis @scene, @camera, @font, @texture
    colocationVis.start network

  addLines: (lines) =>
    linesVis = new LinesVis @scene, @camera, @font, @texture
    linesVis.start lines

  addIntro: =>
    introVis = new IntroVis @scene, @camera, @font, @texture
    introVis.start() 

  setTexture: (@texture) ->
    maxAni = @renderer.getMaxAnisotropy()

    @texture.needsUpdate = true
    @texture.minFilter = THREE.LinearMipMapLinearFilter
    @texture.magFilter = THREE.LinearFilter
    @texture.generateMipmaps = true
    @texture.anisotropy = maxAni

  setFont: (@font) ->

  getTextGeometry: (text) =>
    createGeometry
      text: text
      font: @font

  getTextMesh: (geometry) ->
    material = new THREE.ShaderMaterial(Shader({
      map: @texture,
      smooth: 1/8,
      side: THREE.DoubleSide,
      transparent: true,
      opacity: 0,
      color: 'rgb(10, 10, 10)'
    }))
    mesh = new THREE.Mesh(geometry, material)
    mesh

  getMeshFromString: (string) =>
    string_geom = @getTextGeometry string
    string_mesh = @getTextMesh string_geom
    string_mesh.scale.multiplyScalar(-1)
    string_mesh

  getLineObject: (line) =>
    line_geometry = @getTextGeometry line
    line_layout = line_geometry.layout
    glyph_positions = line_layout.glyphs.map (g) -> g.position

    # if ! line? then debugger

    letterObjects = line.split("").map (letter, index) =>
      assert glyph_positions[index], "#{line} -- #{letter}"
      letter_mesh = @getMeshFromString letter
      letter_mesh.position.x = - glyph_positions[index][0]
      letter_mesh

    # TODO: Pack up words...

    lineObject = new THREE.Object3D()
    lineObject.add.apply lineObject, letterObjects
    lineObject._line = line
    lineObject._layout = line_layout
    lineObject

  panCameraToPosition3: (target, duration, ignoreGlobal) =>
    z_offset = if ignoreGlobal? then 0 else CAMERA_Z
    new Promise (resolve) =>
      d3.transition()
        .duration duration || 1000
        .tween "moveCamera", =>
          current = @camera.position
          x = d3.interpolate(current.x, target.x)
          y = d3.interpolate(current.y, target.y)
          z = d3.interpolate current.z, target.z + z_offset
          (t) =>
            @camera.position.x = x(t)
            @camera.position.y = y(t)
            @camera.position.z = z(t)
        .each "end", resolve

  getBBoxFromSubset: (parent, array) ->
    siblings = parent.children.filter (child) ->
      return array.indexOf(child) < 0
    parent.remove.apply parent, siblings
    box = getBBox parent
    parent.add.apply parent, siblings
    return box

  getBBox = (object) ->
    bbox = new THREE.BoundingBoxHelper( object, 0xff0000 )
    do bbox.update
    return bbox.box
  getBBox: getBBox

  panCameraToObject: (object, duration) =>
    box = getBBox object
    @panCameraToBBox box, duration

  panCameraToBBox: (box, duration) =>
    @panCameraToPosition3 box.center(), duration

  zoomCameraToPosition: (target, duration) =>
    new Promise (resolve) =>
      d3.transition()
        .duration duration
        .tween "zoomCamera", =>
          current = @camera.position
          z = d3.interpolate current.z, target.z
          (t) =>
            @camera.position.z = z(t)
        .each "end", resolve

  addFadeOpacityTransition = (to, duration, target) ->
    (selection) ->
      selection.transition()
        .duration duration
        .delay (_, i) -> i * 10
        .tween "fadeOpacity", ->
          # if target? then debugger
          obj = target || this
          from = obj.material.uniforms.opacity.value
          i = d3.interpolate from, to
          (t) ->
            obj.material.uniforms.opacity.value = i(t)

  fadeToArray = (to, duration) ->
    (array) ->
      new Promise (resolve) ->
        selection = d3.selectAll array
        addFadeOpacityTransition(to, 1000)(selection)
          .each "end", resolve

  fadeToArray: fadeToArray

  _radianScale = d3.scale.linear()
      .domain([0, 360])
      .range([0, Math.PI * 2])

  getZoomDistanceFromBox: (box, distance_scale) ->
    # Calculate horizontal field of view
    # See: github.com/mrdoob/three.js/issues/1239
    v_fov = _radianScale @camera.fov
    h_fov = Math.atan( Math.tan(v_fov/2) * @camera.aspect )

    # See: stackoverflow.com/questions/2866350/move-camera-to-fit-3d-scene
    width = Math.abs(box.min.x - box.max.x)
    return -(width / 2) / Math.tan(h_fov) * distance_scale

  getWordIndex = (line, word) ->
    expression = if word is "—" then word else "\\b#{word}\\b"
    regex = new RegExp expression, "i"
    assert line, "#{line}"
    line.search regex

  getWordIndex: getWordIndex

  alignToNode = (parent) ->
    (child) ->
      parent_x = parent._text_object.position.x
      word = parent.word
      offset = [ parent, child ]
          .map (_) ->
            idx = getWordIndex _.line, word
            assert idx isnt -1, "#{_.line}, #{word}"
            _._text_object.children[idx].position.x
          .reduce (a, b) -> a - b
      child._text_object.position.x = parent_x + offset

  alignToNode: alignToNode

  getLetterObjectsForWord: (text_object, word, accessor) ->
    line = if accessor? then accessor text_object else text_object._line
    # debugger if typeof line isnt "string"
    begin = getWordIndex line, word
    end = begin + word.length
    text_object.children.slice begin, end

  chainedFadeIn: (array, duration) ->
    reduction = (promise, curr, index, array) =>
      promise.then =>
        @fadeToArray(1, 1000) curr._text_object.children

    promise = array.reduce reduction, Promise.resolve()

class LinesVis extends Main
  lineSpacing: 40

  constructor: (@scene, @camera, @font, @texture) ->
    console.info "New LinesVis."

  start: (data) ->
    root = @_addLines data
    @animateLines root

  ########################
  # ANIMATE LINES
  #
  animateLines: (root) =>
    # Fade in the root
    @lines_object.add root._text_object
    @fadeToArray(1, 1000) root._text_object.children
    @panCameraToObject root._text_object
        .then -> traverse root

    traverse = (node) =>
      return if ! node.children?

      next_child = node.children.filter((_) -> _.children?)[0]

      # Start promise chain
      Promise.resolve()
        .then =>
          # Fade out siblings
          if node._parent?
            siblings = node._parent.children
              .filter (child) -> child isnt node
            parent = node._parent
            promises = siblings.concat(parent).map (child) =>
              @fadeToArray(0, 1000) child._text_object.children
                .then => @lines_object.remove child._text_object
            return Promise.all promises
          return true
        .then =>
          # Fade in children
          if next_child?
            promises = node.children.map (child) =>
              @lines_object.add child._text_object
              # Get the array of letters for the target word only
              children = @getLetterObjectsForWord child._text_object, node.word
              @fadeToArray(1, 1000) children
            return Promise.all promises
        .then =>
          # Chained fade-in of child lines
          if next_child?
            pos = node._positions_array
            curr = pos.indexOf(node)
            next = pos.indexOf(next_child)
            if curr < next
              fade_array = pos.slice(curr + 1, next + 1)
            else
              fade_array = pos.slice(next, curr).reverse()
            @chainedFadeIn fade_array, 1000
        .then =>
          if next_child?
            # fadeToArray(1, 1000) next_child._text_object.children
            @panCameraToObject next_child._text_object
        .then ->
          traverse next_child unless ! next_child?

  _addLines: (lines) =>
    lines_object = new THREE.Object3D()
    lines_object.scale.multiplyScalar(@scaleText)
    lines_object.updateMatrixWorld(true)
    @scene.add lines_object

    @lines_object = lines_object

    root = linesToTree lines

    @addObjects(lines_object)(root)

    traverse = (parent) =>
      return if ! parent.children?

      positions_array = d3.shuffle parent.children.concat parent
      parent_index = positions_array.indexOf parent
      parent_y = parent._text_object.position.y

      parent._positions_array = positions_array

      positions_array.forEach (node, index) =>
        offset_from_parent = index - parent_index
        obj = node._text_object
        line_height = obj._layout.height + @lineSpacing
        obj.position.y = parent_y + offset_from_parent * line_height

      parent.children.forEach @alignToNode(parent)
      parent.children.forEach traverse

    traverse root
    return root

  addObjects: (lines_object) =>
    (root) =>
      traverse = (node) =>
        node._text_object = @getLineObject(node.line)
        # lines_object.add node._text_object

        node.children.forEach traverse if node.children

      traverse(root)

  linesToTree = (lines) ->
    lines = lines.map (line) ->
      line: line.line
      word: line.word
      sIdx: line.sIdx
      eIdx: line.eIdx
      children: line.lines

    reducer = (prev, current, index, array) ->
      prev_index = current.children
          .map (_) -> _.line
          .indexOf(prev.line)
      current.children[prev_index] = prev
      prev._parent = current
      current

    lines.reduceRight reducer

class ColocationVis extends Main
  constructor: (@scene, @camera, @font, @texture) ->
    console.info "New ColocationVis."

  rotation: 0

  start: (network) =>
    radius = 700
    rotation = @rotation # Math.PI / 2.2

    network_object = new THREE.Object3D()
    network_object.scale.multiplyScalar(@scaleText)
    network_object.rotateX rotation
    @scene.add network_object

    root = makeTree network
    root = setNetworkPositions root, radius

    @animate root, network_object

  animate: (root, network_object) ->

    traverse = (node) =>
      return if ! node.position?

      node = @setTextObject(node)
      text_object = node._text_object
      text_object.rotateX -@rotation
      network_object.add text_object

      ################################
      # ANIMATE COLOCATION NETWORK
      #
      faded_in = @fadeToArray(1, 1000) text_object.children

      if node.children
        faded_in.then =>
          @panCameraToObject(text_object)
        .then =>
          if node.parent?
            siblings = node.parent.children.filter (child) ->
              return child._text_object isnt text_object
            if node.parent.parent
              siblings = siblings.concat(node.parent.parent)
            promises = siblings.map (sibling) =>
              @fadeToArray(0, 1000) sibling._text_object.children
                .then -> network_object.remove(sibling._text_object)
            return Promise.all promises
        .then ->
          node.children.forEach traverse

    traverse(root)

  setTextObject: (node) =>
    text_object = @getLineObject(node.val)
    text_object.children.forEach (mesh) ->
      mesh.material.uniforms.opacity.value = 0
    text_object.position.copy(node.position)
    node._text_object = text_object
    node

  setNetworkPositions = (root, radius) ->
    root.position = new THREE.Vector3()

    radianScale = d3.scale.ordinal()
        .rangePoints [0, 2 * Math.PI]

    traverse = (node) ->
      return if ! node.children?
      offset = if node.parent? then getRadians(node.parent, node) else 0

      circle_nodes = if node.parent?
        [node.parent].concat(node.children)
      else node.children

      radianScale.domain d3.range(circle_nodes.length + 1)

      circle_nodes.forEach (circle_node, index) ->
        radians = radianScale(index) + offset
        pos = new THREE.Vector3(
          radius * Math.cos(radians) + node.position.x,
          radius * Math.sin(radians) + node.position.y
          # 0,
          # radius * Math.sin(radians) + node.position.z
        )
        if circle_node.position?
          # check = pos.y.toFixed(3) is circle_node.position.y.toFixed(3)
          # assert(check)
        else
          circle_node.position = pos

      if node.children?
        node.children.forEach traverse

    traverse(root)
    return root

  getRadians = (a, b) ->
    dx = a.position.x - b.position.x
    dy = a.position.y - b.position.y
    Math.atan2(dy, dx)

  makeTree = (network) ->
    network = network.map (d) ->
      val: d.word
      children: d.colocations

    _makeTree = (child, parent, index, array) ->
      child.parent = parent

      # Find the index of this child in the parent's children array
      child_index = parent.children
          .map (d) -> d.val
          .indexOf child.val

      # Set the child's "amount" to match the parent's child object
      parents_child = parent.children[child_index]
      child.amt = parents_child.amt

      # Set the parent's reference to match the child object
      parent.children[child_index] = child

      return parent

    network.reduceRight(_makeTree)

class ChainVis extends Main
  constructor: (@scene, @camera, @font, @texture) ->
    console.info "New ChainVis."

  start: (data) =>
    @_addChain data

  _addChain: (text) =>
    lineObjects = @processChain(text)
      .map (line, index) =>
        lineObject = @getLineObject(line.line, index)
        height = lineObject._layout.height
        lineObject.position.y = - (index) * (height + 20)
        lineObject._line = line
        lineObject
      .map positionLines

    chainObject = new THREE.Object3D()
    chainObject.scale.multiplyScalar(@scaleText)

    @scene.add(chainObject)

    ########################
    # ANIMATE POETRY CHAIN
    reducer = (prev, curr, index, array) =>
      prev.then =>
        chainObject.add curr
        word = curr._line.prev_connector
        return if ! word? # word.length is 0
        accessor = (obj) -> obj._line.line
        one_word_array = @getLetterObjectsForWord curr, word, accessor
        bbox = @getBBoxFromSubset curr, one_word_array
        return @fadeToArray(1, 1000) one_word_array
        # return @panCameraToBBox bbox, 1000
      .then =>
        bbox = @getBBox chainObject
        x = bbox.center().x
        y = bbox.center().y
        z = bbox.center().z + @getZoomDistanceFromBox bbox, 1.3
        @panCameraToPosition3 new THREE.Vector3(x,y,z), 1000, true
        @fadeToArray(1, 1000) curr.children

    first = Promise.resolve()
    lineObjects.reduce reducer, first

  positionLines = (line, index, array) ->
    return line if index is 0

    prev = array[index - 1]
    prev_connector_idx = prev._line.connector_index
    my_prev_connector_idx = line._line.my_prev_connector_index

    line.position.x = prev.position.x
    line.position.x += prev.children[prev_connector_idx].position.x
    line.position.x -= line.children[my_prev_connector_idx].position.x
    line

  processChain: (chain) ->
    chain.map (obj, i, array) =>
      obj.connector_index = obj.line.indexOf obj.connector
      if i > 0
        prev = array[i-1]
        prev_con = prev.connector
        # my_prev_idx = obj.line.indexOf prev_con
        my_prev_idx = @getWordIndex obj.line, prev_con
        prev_idx = prev.connector_index
        obj.prev_connector = prev_con
        obj.my_prev_connector_index = my_prev_idx
        obj.prev_connector_index = prev_idx
      obj



class IntroVis extends Main
  constructor: (@scene, @camera, @font, @texture) ->
    console.info "New IntroVis."

  start: =>
    @_addIntro()

  _addIntro: =>
    lineObject = @getLineObject("Intro Hello Chains!")

    @scene.add(lineObject)


