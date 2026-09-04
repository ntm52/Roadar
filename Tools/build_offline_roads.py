#!/usr/bin/env python3
"""Build Roadar's indexed, read-only road package from a Geofabrik Michigan PBF.
Requires osmium==4.3.1. No routing or implied/default speed limits are generated.
"""
import argparse
import hashlib
import gzip
import shutil
import json
import math
import re
import sqlite3
import struct
from pathlib import Path
import osmium

BOUNDS = (-87.0, 41.65, -82.1, 42.90)
HIGHWAYS = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified',
            'residential', 'living_street', 'service', 'road', 'track',
            'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link'}

def speed(tags, direction):
    # Conditional/lane/variable limits require semantics this version cannot establish.
    if any(k.startswith('maxspeed') and ('conditional' in k or 'lanes' in k or 'variable' in k) for k in tags):
        return None
    raw = tags.get('maxspeed:' + direction, tags.get('maxspeed', '')).strip()
    m = re.fullmatch(r'(\d+(?:\.\d+)?)\s*(mph|km/h|kmh|kph)?', raw)
    if not m:
        return None
    value = float(m[1])
    unit = 'mph' if m[2] == 'mph' else 'km/h'
    if value <= 0 or value > (100 if unit == 'mph' else 160):
        return None
    return f'{value:g} {unit}'

def directions(tags):
    if any(k.startswith('oneway') and 'conditional' in k for k in tags):
        return 0  # unknown direction: useful as an ambiguity candidate, never a match
    value = tags.get('oneway:motor_vehicle', tags.get('oneway', ''))
    if value in ('yes', '1', 'true'): return 1
    if value == '-1': return -1
    if value in ('no', '0', 'false'): return 2
    if value: return 0
    if tags.get('junction') == 'roundabout' or tags.get('highway') == 'motorway': return 1
    return 2

def inside(lon, lat):
    w, s, e, n = BOUNDS
    return w <= lon <= e and s <= lat <= n

class Builder(osmium.SimpleHandler):
    def __init__(self, db):
        super().__init__()
        self.db = db
        self.count = 0
        self.known = 0
        self.length = 0
        self.known_length = 0

    def way(self, way):
        tags = dict(way.tags)
        if tags.get('highway') not in HIGHWAYS or tags.get('area') == 'yes': return
        # Split at the crop, rather than reconnecting points across missing geometry.
        runs, run = [], []
        for node in way.nodes:
            if node.location.valid() and inside(node.lon, node.lat):
                run.append([node.lon, node.lat, node.ref])
            else:
                if len(run) > 1: runs.append(run)
                run = []
        if len(run) > 1: runs.append(run)
        forward, backward = speed(tags, 'forward'), speed(tags, 'backward')
        direction = directions(tags)
        for points in runs:
            self.count += 1
            name = tags.get('name') or tags.get('ref') or 'Unnamed road'
            xs, ys = [p[0] for p in points], [p[1] for p in points]
            length = sum(math.hypot((b[0]-a[0])*111195*math.cos(math.radians((a[1]+b[1])/2)),
                                    (b[1]-a[1])*111195) for a,b in zip(points, points[1:]))
            known = direction != 0 and ((direction == 1 and forward) or (direction == -1 and backward)
                    or (direction == 2 and forward and backward))
            self.length += length
            if known:
                self.known += 1
                self.known_length += length
            self.db.execute('INSERT INTO roads VALUES (?,?,?,?,?,?,?,?,?)',
                (self.count, way.id, name, direction, forward, backward,
                 b''.join(struct.pack('<iiq', round(p[0]*1e7), round(p[1]*1e7), p[2]) for p in points), tags.get('layer', '0'), tags.get('highway')))
            self.db.execute('INSERT INTO bounds VALUES (?,?,?,?,?)',
                (self.count, min(xs), max(xs), min(ys), max(ys)))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.output.exists(): raise SystemExit('Output exists; choose a new output path.')
    reader = osmium.io.Reader(str(args.source))
    timestamp = reader.header().get('osmosis_replication_timestamp')
    reader.close()
    if not timestamp: raise SystemExit('Source lacks replication timestamp.')
    db = sqlite3.connect(args.output)
    db.executescript('''
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA user_version=1;
        PRAGMA application_id=1380925764;
        CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE roads (id INTEGER PRIMARY KEY, osm_id INTEGER, name TEXT, direction INTEGER,
                            forward_limit TEXT, backward_limit TEXT, points BLOB, layer TEXT, highway TEXT);
        CREATE VIRTUAL TABLE bounds USING rtree(id, min_lon, max_lon, min_lat, max_lat);
    ''')
    handler = Builder(db)
    handler.apply_file(str(args.source), locations=True, idx='flex_mem')
    metadata = {'schema': 1, 'regionID': 'southern-michigan', 'name': 'Southern Michigan',
        'bounds': list(BOUNDS), 'sourceDate': timestamp, 'roadCount': handler.count,
        'knownLimitRoadCount': handler.known, 'roadKilometers': round(handler.length/1000),
        'knownLimitKilometers': round(handler.known_length/1000),
        'attribution': '© OpenStreetMap contributors', 'license': 'ODbL-1.0',
        'sourceURL': 'https://download.geofabrik.de/north-america/us/michigan.html',
        'scope': 'Michigan source roads south of 42.90°N. Offline road context only; no offline basemap, search or routing.'}
    db.execute('INSERT INTO metadata VALUES (?,?)', ('manifest', json.dumps(metadata)))
    db.commit()
    db.execute('VACUUM')
    assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    db.close()
    metadata['installedBytes'] = args.output.stat().st_size
    archive = args.output.with_suffix('.roadar.gz')
    with args.output.open('rb') as source, archive.open('wb') as target:
        with gzip.GzipFile(filename='', mode='wb', fileobj=target, mtime=0) as compressed:
            shutil.copyfileobj(source, compressed)
    metadata['bytes'] = archive.stat().st_size
    metadata['sha256'] = hashlib.sha256(archive.read_bytes()).hexdigest()
    metadata['downloadURL'] = None
    args.output.with_suffix('.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(json.dumps(metadata, indent=2))

if __name__ == '__main__': main()
