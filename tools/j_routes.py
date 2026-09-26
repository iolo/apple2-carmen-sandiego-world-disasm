"""Decode and rebuild J's eight 30-city travel graphs."""


CITY_COUNT = 30
GRAPH_COUNT = 8
PAGE_SIZE = 256
DATA_LIMIT = 0xD8
OFFSET_END = DATA_LIMIT + CITY_COUNT + 1


def _validate_routes(routes):
    edges = {(city, destination) for city, destinations in enumerate(routes)
             for destination in destinations}
    for city, destinations in enumerate(routes):
        if not 3 <= len(destinations) <= 5:
            raise ValueError(f"city {city}: expected 3-5 routes")
        if len(set(destinations)) != len(destinations):
            raise ValueError(f"city {city}: duplicate destination")
        for destination in destinations:
            if not 0 <= destination < CITY_COUNT or destination == city:
                raise ValueError(f"city {city}: invalid destination {destination}")
            if (destination, city) not in edges:
                raise ValueError(f"city {city}: route to {destination} is not reciprocal")


def decode_j(data, names):
    if len(data) != GRAPH_COUNT * PAGE_SIZE or len(names) != CITY_COUNT:
        raise ValueError("Unexpected J size or city-name count")
    graphs = []
    for number in range(GRAPH_COUNT):
        page = data[number * PAGE_SIZE:(number + 1) * PAGE_SIZE]
        offsets = list(page[DATA_LIMIT:OFFSET_END])
        if offsets[0] != 0 or offsets != sorted(offsets) or offsets[-1] > DATA_LIMIT:
            raise ValueError(f"J graph {number}: invalid route offsets")
        if any(page[offsets[-1]:DATA_LIMIT]) or any(page[OFFSET_END:]):
            raise ValueError(f"J graph {number}: nonzero padding")
        routes = [list(page[offsets[city]:offsets[city + 1]])
                  for city in range(CITY_COUNT)]
        _validate_routes(routes)
        graphs.append({"number": number,
                       "routes": {names[city]: [names[destination] for destination in routes[city]]
                                  for city in range(CITY_COUNT)}})
    return {"graphs": graphs}


def encode_j(source, names):
    graphs = source["graphs"]
    if len(graphs) != GRAPH_COUNT or len(names) != CITY_COUNT or len(set(names)) != CITY_COUNT:
        raise ValueError("Expected eight graphs and 30 distinct city names")
    indices = {name: index for index, name in enumerate(names)}
    pages = []
    for number, graph in enumerate(graphs):
        if graph["number"] != number or set(graph["routes"]) != set(names):
            raise ValueError(f"J graph {number}: incorrect city set or order")
        routes = [[indices[destination] for destination in graph["routes"][name]]
                  for name in names]
        _validate_routes(routes)
        offsets = [0]
        route_bytes = bytearray()
        for destinations in routes:
            route_bytes.extend(destinations)
            offsets.append(len(route_bytes))
        if len(route_bytes) > DATA_LIMIT:
            raise ValueError(f"J graph {number}: route list exceeds page data area")
        pages.append(bytes(route_bytes).ljust(DATA_LIMIT, b"\0")
                     + bytes(offsets) + b"\0" * (PAGE_SIZE - OFFSET_END))
    return b"".join(pages)
