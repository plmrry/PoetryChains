d3 = require "d3"
Vis = require "./vis"

vis = new Vis()

do ->
    font_loaded = new Promise (resolve) ->
        do vis.animate

        require('./load')({
            # font: 'fnt/DejaVu-sdf.fnt',
            # image: 'fnt/DejaVu-sdf.png'
            # font: "fnt/Lato-Regular-64.fnt",
            # image: "fnt/lato.png"
            # font: "fnt/test-font.fnt",
            # image: "fnt/test-font.png"
            font: "fnt/Palatino-Linotype.fnt",
            image: "fnt/Palatino-Linotype.png"
        }, (font, texture) -> resolve({ font: font, texture: texture }))

    font_loaded.then (obj) ->
        vis.setTexture(obj.texture)
        vis.setFont(obj.font)
    .then ->
        switch window.location.hash
            when "", "#chain" then do chainMode
            when "#colocation" then do colocationMode
            when "#lines" then do linesMode

    apiUrl = (call) ->
        "#{window.location.origin}/api/#{call}"

    getJson = (apiCall, message) ->
        new Promise (resolve) ->
            console.info message
            url = apiUrl apiCall
            d3.json url, resolve

    linesMode = ->
        console.info "Starting Lines Mode."
        getJson "get-lines.json", "Requesting Lines..."
            .then vis.addLines

    chainMode = ->
        console.info "Starting Chain Mode."
        getJson "get-chain.json", "Requesting poetry chain..."
            .then (d) ->
                d.forEach (chain) ->
                    chain.forEach (line) ->
                        line.line = line.line.replace("--", "—")
                        line.line = line.line.replace("––", "—")
                        line.line = line.line.replace("——", "—")
                vis.addChain d[0]

    colocationMode = ->
        console.info "Starting Colocation Mode."
        getJson "get-colocation.json", "Requesting colocation network..."
            .then vis.addNetwork
