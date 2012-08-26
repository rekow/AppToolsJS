
class t

  blockregex = /\{\{\s*?(([@!>]?)(.+?))\s*?\}\}(([\s\S]+?)(\{\{\s*?:\1\s*?\}\}([\s\S]+?))?)\{\{\s*?\/(?:\1|\s*?\3\s*?)\s*?\}\}/g
  valregex = /\{\{\s*?([<&=%])\s*?(.+?)\s*?\}\}/g

  constructor: (template) ->

    @scrub = (val) =>
      return new Option(val).innerHTML.replace(/["']/g, '&quot;')

    @get_value = (vars, key) =>
      return @render(vars[key], @get_value(vars, 'context')) if key is 'template'
      parts = key.split('.')
      while parts.length
        return false if parts[0] not of vars
        vars = vars[parts.shift()]

      return (if typeof vars is 'function' then vars() else vars)

    @t = template
    @temp = []
    return @

  render: (fragment, vars) =>
    @temp = []
    if not vars?
      vars = fragment
      fragment = @t

    return fragment.replace(blockregex, (_, __, meta, key, inner, if_true, has_else, if_false) =>
      val = @get_value(vars, key)
      temp = ''

      if not val
        return (if meta is '!' then @render(inner, vars) else (if has_else then @render(if_false, vars) else ''))

      if not meta
        return @render(`has_else ? if_true : inner, vars`)

      if meta is '@'
        for k, v of val
          if val.hasOwnProperty(k)
            temp += @render(inner, {_key: k, _val: v})

      if meta is '>'
        if Array.isArray(val) or val.constructor.name is 'ListField'
          temp += @render(inner, item) for item in val
        else temp += @render(inner, val)

      return temp
    ).replace(valregex, (_, meta, key) =>
      return @temp[parseInt(key)-1] if meta is '&'
      val = @get_value(vars, key)
      @temp.push(val) if meta is '<'
      return (if val? then (if meta is '%' then @scrub(val) else val) else '')
    )

window.t = t
