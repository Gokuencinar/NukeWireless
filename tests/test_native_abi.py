"""Read the pinned Mach-O's Objective-C metadata; never execute the app."""
import struct
from test_package import BASE, members
from build_nuke_info_deb import APP

data = members(BASE, 'data.tar')[APP+'HarpyReloaded'][1]
def u64(offset): return struct.unpack_from('<Q', data, offset)[0]
def u32(offset): return struct.unpack_from('<I', data, offset)[0]
segments = []
sections = {}
offset = 32
assert u32(0) == 0xfeedfacf
for _ in range(u32(16)):
    command, size = struct.unpack_from('<II', data, offset)
    if command == 0x19:
        _, address, length, fileoff, _, _, _, count, _ = struct.unpack_from('<16sQQQQiiII', data, offset+8)
        segments.append((address, length, fileoff))
        for index in range(count):
            name, _, address, length, fileoff = struct.unpack_from('<16s16sQQI', data, offset+72+80*index)
            sections[name.rstrip(b'\0').decode()] = (address, length, fileoff)
    offset += size

def file_offset(address):
    for start, length, offset in segments:
        if start <= address < start+length: return address-start+offset
    raise ValueError(hex(address))
def string(address):
    offset = file_offset(address)
    return data[offset:data.index(b'\0', offset)].decode()
def class_ro(address): return file_offset(u64(file_offset(address)+32) & ~7)
def methods(address):
    if not address: return {}
    offset = file_offset(address)
    flags, count = struct.unpack_from('<II', data, offset)
    result = {}
    for index in range(count):
        offset_in_list = 8+index*(flags & 0xffff)
        entry = offset+offset_in_list
        if flags & 0x80000000:
            name, types, _ = struct.unpack_from('<iii', data, entry)
            name += address+offset_in_list
            types += address+offset_in_list+4
            if not flags & 0x40000000: name = u64(file_offset(name))
        else:
            name, types = u64(entry), u64(entry+8)
        result[string(name)] = string(types)
    return result

classes = {}
_, length, offset = sections['__objc_classlist']
for entry in range(offset, offset+length, 8):
    address = u64(entry); ro = class_ro(address)
    name = string(u64(ro+24))
    if name in ['MMLANScanner','_TtC13HarpyReloaded10LanScanner','_TtC13HarpyReloaded10MCCommands']:
        classes[name] = (methods(u64(ro+32)), methods(u64(class_ro(u64(file_offset(address)))+32)))

scanner = classes['MMLANScanner'][0]
adapter = classes['_TtC13HarpyReloaded10LanScanner'][0]
commands = classes['_TtC13HarpyReloaded10MCCommands'][1]
assert scanner['initWithDelegate:andEnableHotspot:'] == '@28@0:8@16B24'
assert scanner['start'] == scanner['stop'] == 'v16@0:8'
assert 'start' not in adapter and 'initWithDelegate:andEnableHotspot:' not in adapter
assert adapter['lanScanDidFinishScanningWithStatus:'] == 'v20@0:8i16'
assert adapter['lanScanProgressPinged:from:'] == 'v28@0:8f16q20'
assert adapter['lanScanDidFindNewDevice:'] == 'v24@0:8@16'
assert commands['blockGivenIPWithIp:targetMac:'] == 'v32@0:8@16@24'
assert commands['unblockIPWithIp:'] == 'v24@0:8@16'
assert commands['runningBlocksForIpWithIp:'] == '@24@0:8@16'
assert commands['gatewayIP'] == '@16@0:8'
print('PASS: native scanner class, adapter callbacks and shared individual/bulk command ABI')
