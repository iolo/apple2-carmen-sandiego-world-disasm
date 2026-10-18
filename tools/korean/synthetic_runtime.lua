-- Evidence from the disk-booted synthetic game, not a RAM-installed renderer.
local json=require('json')
local k=assert(_G.carmen_korean_runtime,'load start.lua first')
local mode=_G.carmen_korean_mode or 'synthetic'
assert(mode=='synthetic' or mode=='approved','unknown runtime mode')
local function file(path)
    local f=assert(io.open(path,'rb'));local b=f:read('a');f:close();return b
end
local function space() return manager.machine.devices[':maincpu'].spaces.program end
local function read(address,count)
    local b={};for i=0,count-1 do b[#b+1]=string.char(space():read_u8(address+i)) end
    return table.concat(b)
end
local function select(bank)
    local s=space();s:write_u8(0xC002,0);s:write_u8(0xC004,0)
    s:read_u8(0xC083);s:read_u8(0xC083)
    if bank=='lc1' then s:read_u8(0xC08B);s:read_u8(0xC08B)
    elseif bank=='aux' then s:write_u8(0xC003,0);s:write_u8(0xC005,0) end
end
local state={manifest=json.parse(file(k.root..'/build/korean/'..mode..'/manifest.json')),
             library=json.parse(file(k.root..'/build/korean/library/manifest.json')),expected={}}
state.captions=json.parse(file(k.root..'/build/korean/'..mode..'/captions/manifest.json'))
for name,record in pairs(state.manifest.files) do
    if name=='C' or name=='D' or name=='I' or name=='K' or name=='N' or name=='R' then
        state.expected[name]=file(k.root..'/build/korean/'..mode..'/text/'..name..'.bin')
    end
end
state.expected.KF=file(k.root..'/build/korean/draft-fixtures/KF.bin')
state.expected.KL=file(k.root..'/build/korean/library/KL.bin')
state.expected.caption_engine=file(k.root..'/build/korean/'..mode..'/captions/engine.bin')

function a2.korean_synthetic_check(name,module)
    assert(name:match('^[a-z0-9_-]+$'))
    assert(a2.status().debugger=='stop','instruction boundary required')
    local result=a2.korean_checkpoint(name)
    local m=result.mapping
    assert(m.ALTZP and m.LCBANK2 and m.LCRAM and not m.RAMRD and not m.RAMWRT and not m.STORE80,'unexpected game mapping')
    if mode=='synthetic' then result.synthetic_image_sha256=state.manifest.image_sha256
    else result.mode=mode;result.image_sha256=state.manifest.image_sha256;result.catalog_sha256=state.manifest.catalog_sha256;result.approval_sha256=state.manifest.build_inputs.approval_sha256 end
    result.full_byte_comparisons={}
    local tests=result.full_byte_comparisons
    select('lc1');tests.font_first_4096=read(0xD000,4096)==state.expected.KF:sub(1,4096)
    select('aux');tests.font_remainder=read(0xA700,#state.expected.KF-4096)==state.expected.KF:sub(4097)
    tests.treasures=read(0x6000,#state.expected.I)==state.expected.I
    tests.clues=read(0x5000,#state.expected.K)==state.expected.K
    select('main');tests.resident_c=read(0xD200,#state.expected.C)==state.expected.C
    tests.original_font_and_clock_bitmaps=read(0xB900,#state.expected.D)==state.expected.D
    local sym=state.library.symbols
    tests.font_copy_helper=read(0xD100,sym.K_HELPER_BYTES)==state.expected.KL:sub(sym.K_HELPER_SOURCE-0x9200+1,sym.K_HELPER_SOURCE-0x9200+sym.K_HELPER_BYTES)
    local library=read(0x9200,#state.expected.KL)
    local mutable={}
    for _,label in ipairs({'K_LOAD_FIRST','K_LOAD_TRAIL','K_ADVANCE_BYTE','K_ADVANCE_HIGH'}) do mutable[sym[label]+1]=true end
    local intact=true
    for i=1,#library do
        local address=0x9200+i-1
        if address<sym.K_PENDING and not mutable[address] and library:byte(i)~=state.expected.KL:byte(i) then intact=false end
    end
    tests.resident_library_instructions=intact
    local cap=state.captions
    local bytes=read(cap.address,cap.bytes)
    local mutable={};for _,address in ipairs(cap.mutable_operands) do mutable[address]=true end
    intact=true
    for i=1,#bytes do
        local address=cap.address+i-1
        if address<cap.mutable_data_start and not mutable[address] and bytes:byte(i)~=state.expected.caption_engine:byte(i) then intact=false end
    end
    tests.caption_engine_immutable=intact
    if module then
        assert(module=='N' or module=='R')
        tests.overlay_before_execution=read(0x6000,#state.expected[module])==state.expected[module]
    end
    result.decoder_error=space():read_u8(sym.K_ERROR)
    for label,passed in pairs(tests) do assert(passed,'synthetic bytes differ: '..label) end
    assert(result.decoder_error==0,'synthetic decoder rejected a game glyph')
    local f=assert(io.open(k.work..'/'..name..'-'..mode..'.json','wb'));f:write(json.stringify(result));f:write('\n');f:close()
    return result
end

return {loaded=true,mode=mode,image_sha256=state.manifest.image_sha256}
