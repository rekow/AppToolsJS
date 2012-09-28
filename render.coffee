#### === Render/DOM Interfaces === ####
class DOMInterface extends Interface

    capability: 'dom'
    required: []

class QueryInterface extends Interface

    capability: 'query'
    parent: DOMInterface
    required: ['element_by_id', 'elements_by_class', 'elements_by_tag', 'get']

    get: (selector) ->
    element_by_id: (id) ->
    elements_by_tag: (tagname) ->
    elements_by_class: (classname) ->

class RenderInterface extends Interface

    capability: 'render'
    parent: DOMInterface
    required: []

    render: (template, context) ->

class AnimationInterface extends Interface

    capability: 'animation'
    parent: DOMInterface
    required: ['animate']

    animate: (to, settings) ->


#### === Core Render Classes === ####
class CoreRenderAPI extends CoreAPI

    @mount = 'render'
    @events = []
    @export = 'private'

    constructor: (apptools, window) ->
        return @

class RenderException extends CoreException

class Template

    @export = 'public'
    @idx = 0
    @uuid = () ->
        return _.zero_fill(@idx++, 3)

    blockre = /\{\{\s*?(([@!>]?)(.+?))\s*?\}\}(([\s\S]+?)(\{\{\s*?:\1\s*?\}\}([\s\S]+?))?)\{\{\s*?\/(?:\1|\s*?\3\s*?)\s*?\}\}/g
    valre = /\{\{\s*?([<&=%+])\s*?(.+?)\s*?\}\}/g
    tagre = /\{\{[\w\W.]*\}\}/
    fnre = /function\s?(\w*)\s?\(([\w\W.]*)\)\s?\{([\w\W.]*)\}/
    _re = /[\r\n\t]/g

    constructor :(source, compile=false, name) ->

        @t = source.replace(_re, '')
        @name = if name? then name else 'template'+Template.uuid()

        @temp = []

        @compile = () => return Template::compile.apply(@, arguments)
        @bind = () => return Template::bind.apply(@, arguments)

        return (if !!compile then (if compile.nodeType then @compile(@bind(compile)) else @compile(@)) else @)

    bind: (element) ->
        delete @bind

        @node = element
        @env = document.createElement(@node.tagName)

        return @

    compile: (th, strvar='str', ctxvar='ctx') ->

        name = th.name
        template = th.t
        nodestr = name+'.node'

        console.log('[Render]', 'Compiling AppTools JS template:', name)

        depth = -1

        functionize = (string) =>

            b = ''
            ctxnow = if depth > -1 then '_val' else ctxvar

            live = string.match(tagre)
            live = if !!live then live[0] else string
            index = (if !!~string.search(tagre) then string.search(tagre) else string.length)
            start = @safe(string.slice(0, index))
            end = @safe(string.slice(live.length + index))

            b += '\'' + start if start.length > 0
            b += live.replace(blockre, (_, __, meta, key, inner, if_true, has_else, if_false) =>
                temp = if start.length > 0 then '\';' else ''
                keystr = [ctxnow, key].join('.')

                if meta is '' or not meta
                    temp += 'if(!!'+keystr+'){'+ functionize(if_true)
                    temp += 'else{'+ functionize(if_false) if has_else

                else if meta is '!'
                    temp += 'if(!'+keystr+'){ '+strvar+'+=' + functionize(inner)

                else if meta is '@' or meta is '>'

                    loopstr = '_'+key.slice(0, 2) + key.slice(key.length - 2)
                    loopvar = '_'+loopstr
                    _valstr = loopstr+'['+loopvar+']'

                    depth++ if meta is '>'

                    temp += 'var '+loopstr+'='+keystr+';for(var '+loopvar+' in '+loopstr+'){'
                    temp += if meta is '@' then ctxvar+'._key='+loopvar+';'+ctxvar+'._val='+_valstr else '_val='+_valstr
                    temp += ';'+strvar+'+='
                    temp += functionize(inner)
                    if meta is '>'
                        temp += ';_val=null;'
                        depth--

                temp += '}'
                temp += strvar+'+=\'' if end.length > 0

                return temp
            ).replace(valre, (_, meta, key) =>
                if meta is '+'
                    child = new Function('','return this.'+key+';')()
                    return '' if not child?
                    valstr = 'this.'+key+'(false,'+ctxnow+')'
                    child = if typeof child isnt 'function' then (if child.t then (child.name = key; child.compile(child)) else new Template(child, true, key);) else child
                    return valstr
                else
                    valstr = [ctxnow, key].join('.')
                    return '\'+'+ (if meta is '%' then 'Template.prototype.scrub('+valstr+')' else valstr) + '+\''
            )
            b += '\'+\'' + end + '\'' if end.length > 0
            return b

        body = ['this.'+name+' = (function() {',
            name + '.name = \''+name+'\';',
            'function '+name+' ('+ctxvar+') {',
            'var _val,n='+nodestr+',',
            'dom=(typeof '+ctxvar+'==\'boolean\')?',
            '(c = '+ctxvar+', '+ctxvar+' = arguments[1], c)',
            ':true;var '+strvar+'=',
            functionize(template),
            ';return (dom && n != null)?',
            'n.outerHTML='+strvar,
            ':'+strvar+';}',
            'return '+name+';}).call(this);',
            'return this.'+name+';'
        ].join('')

        f = new Function('', body)()
        if th.env?
            f.node = th.node
        else
            f.bind = (el) ->
                @node = el
                delete @bind
                return @node

        console.log('[Render]', 'Template compiled:', String(f).replace(/\{[\w\W.]*\}/, '{...}'))

        return f

    parse: (fragment, vars) ->
        if not vars?
            vars = fragment
            fragment = @t

        vars = vars._ctx if vars._ctx

        return if vars.tag and vars.attrs then _create_element_string(vars.tag, vars.attrs, vars.separator) else fragment.replace(blockre, (_, __, meta, key, inner, if_true, has_else, if_false) =>
            val = @get_value(vars, key)
            temp = ''

            if not val
                return (if meta is '!' then @parse(inner, vars) else (if has_else then @parse(if_false, vars) else ''))

            if not meta
                return @parse(if has_else then if_true else `inner, vars`)

            if meta is '@'
                for k, v of val
                    temp += @parse(inner, {_key: k, _val: v}) if val.hasOwnProperty(k)

            if meta is '>'
                if Array.isArray(val) or val.constructor.name is 'ListField'
                    temp += @parse(inner, {_ctx: item}) for item in val
                else temp += @parse(inner, {_ctx: val})

            return temp
        ).replace(valre, (_, meta, key) =>
            return @temp[parseInt(key)-1] if meta is '&'
            val = @get_value(vars, key)
            @temp.push(val) if meta is '<'
            return (if val? then (if meta is '%' then @scrub(val) else val) else '')
        )

    unparse: (element) ->

        elobj = {attributes: {}}
        parent = element.parentNode
        depth = 0

        elobj.tagName = element.tagName
        elobj.attributes[attr.name] = attr.nodeValue for attr in element.attributes
        elobj.innerHTML = element.innerHTML

        if not parent.hasAttribute('id')
            while (depth++; parent = parent.parentNode)
                continue if not parent.hasAttribute('id')
                break

        elobj.parent = parent.getAttribute('id')
        elobj.depth = depth

        return elobj

    scrub: (val) ->
        return new Option(val).innerHTML.split('\'').join('&#39;').split('"').join('&quot;')

    safe: (val) ->
        return val.split('\'').join('&#39;').split('"').join('&quot;')

    get_value: (vars, key) ->
        parts = key.split('.')
        while parts.length
            return false if parts[0] not of vars
            vars = vars[parts.shift()]

        return (if typeof vars is 'function' then vars() else vars)

    template: (@t) ->
        return @

    render: (ctx) ->
        dom = if typeof ctx is 'boolean' then (c = ctx; ctx = arguments[1]; c) else true

        return false if not ctx?

        html = @parse(ctx)
        return html if not dom or not @env?

        @env.appendChild(@node.cloneNode(false))
        @env.firstChild.outerHTML = html

        newnode = @env.firstChild

        if dom
            @node.parentNode.insertBefore(newnode, @node)

        @node = newnode
        return @node

window.t = Template

class TemplateLoader
    # takes remote template path & returns via service layer call
    constructor: () ->

        @load = (pre_template) =>
            console.log(@constructor.name, 'Loading templates from a remote service is currently stubbed.')
            return pre_template

        return @



@__apptools_preinit.abstract_base_classes.push  QueryInterface,
                                                RenderInterface,
                                                AnimationInterface,
                                                RenderException,
                                                Template,
                                                TemplateLoader,
                                                CoreRenderAPI

@__apptools_preinit.abstract_feature_interfaces.push DOMInterface,
                                                     QueryInterface,
                                                     RenderInterface,
                                                     AnimationInterface
