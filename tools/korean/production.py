"""Build the Korean 800K image only from the exact human-approved catalog."""

import argparse

from .approval import require


def build():
    require()  # Fail before importing compilers or creating output directories.
    from .capacity import symbols
    from .common import BUILD
    (BUILD / "maps").mkdir(parents=True, exist_ok=True)
    for module in ("WORLD.SYSTEM", "B", "C", "N", "R"):
        symbols(module, BUILD / "maps")
    from .synthetic import build as image
    return image(approved=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        build()
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.error(str(error))


if __name__ == '__main__':
    main()
