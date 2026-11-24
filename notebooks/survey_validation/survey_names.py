"""Survey game names -> the title to look up, with a recorded reason and confidence.

Rules (from the task):
- typos -> the obvious title;
- a series without a number -> the respondent's most plausible entry given their hours and
  status, else the most recent main entry;
- every decision is recorded. "low" marks a judgement call for review.

DECISIONS is keyed by the casefolded, stripped raw name. SERIES_BY_RESPONDENT overrides it for
a (respondent, raw name) pair when the plausible entry depends on that respondent's answers.
"""
from __future__ import annotations

HIGH, LOW = "high", "low"

# raw name (casefolded, stripped) -> (title to look up, confidence, reason)
DECISIONS: dict[str, tuple[str, str, str]] = {
    "a way out": ("A Way Out", HIGH, "exact title"),
    "arc riders": ("ARC Raiders", HIGH, "typo: Riders -> Raiders"),
    "assasians creed mirage": ("Assassin's Creed Mirage", HIGH, "typo"),
    "batman arkham night": ("Batman: Arkham Knight", HIGH, "typo: Night -> Knight"),
    "beamng drive": ("BeamNG.drive", HIGH, "exact title"),
    "burglin gnomes": ("Burglin' Gnomes", HIGH, "exact title (apostrophe)"),
    "clair obscure expedition 33": ("Clair Obscur: Expedition 33", HIGH, "typo: Obscure -> Obscur"),
    "expedition 33": ("Clair Obscur: Expedition 33", HIGH, "short title"),
    "clash royale": ("Clash Royale", HIGH, "exact title (mobile)"),
    "cuphead": ("Cuphead", HIGH, "exact title"),
    "dead by daylight": ("Dead by Daylight", HIGH, "exact title"),
    "death stranding": ("Death Stranding", HIGH, "the first game; the sequel is numbered (Death Stranding 2)"),
    "detroit": ("Detroit: Become Human", HIGH, "short title; the only game in the series"),
    "dispatch": ("Dispatch", HIGH, "exact title (AdHoc Studio, 2025)"),
    "elden ring": ("Elden Ring", HIGH, "exact title"),
    "fall guys": ("Fall Guys", HIGH, "exact title"),
    "fc 24": ("EA Sports FC 24", HIGH, "short title"),
    "fc 26(there’s a theme\U0001fae0)": ("EA Sports FC 26", HIGH, "short title; the comment is ignored"),
    "fc 27": ("EA Sports FC 27", HIGH, "short title"),
    "fc27,": ("EA Sports FC 27", HIGH, "short title; trailing comma"),
    "fifa27": ("EA Sports FC 27", LOW, "there is no FIFA 27; EA's football series is called EA Sports FC since 2023"),
    "final fantasy xvi": ("Final Fantasy XVI", HIGH, "exact title"),
    "five m": ("Grand Theft Auto V", LOW,
               "FiveM is a GTA V multiplayer modification, not a separate game; mapped to GTA V"),
    "five nights at freddy": ("Five Nights at Freddy's", LOW,
                              "series name; 200+ hours suggests the whole series, mapped to the first game"),
    "fortnight": ("Fortnite", HIGH, "typo"),
    "fortnite": ("Fortnite", HIGH, "exact title"),
    "god of war": ("God of War", LOW,
                   "'God of War' is both the 2005 original and the 2018 game; the 2018 game is the most plausible "
                   "(26-50 h, finished, 100% trophies) and the most recent main entry with that title"),
    "gow ragnarok": ("God of War Ragnarök", HIGH, "abbreviation"),
    "grand theft auto 5": ("Grand Theft Auto V", HIGH, "number written as 5"),
    "gta v": ("Grand Theft Auto V", HIGH, "abbreviation"),
    "gta5": ("Grand Theft Auto V", HIGH, "abbreviation"),
    "gta": ("Grand Theft Auto V", LOW, "series without a number; 200+ hours and finished fits GTA V best"),
    "grand theft auto 6": ("Grand Theft Auto VI", LOW, "number written as 6; check whether it was out when answered"),
    "gta6": ("Grand Theft Auto VI", LOW, "abbreviation; check whether it was out when answered"),
    "hogwarts legacy": ("Hogwarts Legacy", HIGH, "exact title"),
    "hollow knight": ("Hollow Knight", HIGH, "exact title"),
    "hollow knight: silksong": ("Hollow Knight: Silksong", HIGH, "exact title"),
    "silksong": ("Hollow Knight: Silksong", HIGH, "short title"),
    "lego batman legacy of the dark knight": ("LEGO Batman: Legacy of the Dark Knight", HIGH, "exact title"),
    "mario kart world": ("Mario Kart World", HIGH, "exact title (Switch 2)"),
    "marvel contest of champions": ("Marvel Contest of Champions", HIGH, "exact title (mobile)"),
    "marvel rivals": ("Marvel Rivals", HIGH, "exact title"),
    "meccha chameleon": ("Mecha Chameleon", LOW, "unfamiliar title; spelling variants merged, lookup decides"),
    "mecha chameleon": ("Mecha Chameleon", LOW, "unfamiliar title; lookup decides"),
    "mine craft": ("Minecraft", HIGH, "typo"),
    "minecraft": ("Minecraft", HIGH, "exact title"),
    "nba 2k26": ("NBA 2K26", HIGH, "exact title"),
    "no more heros": ("No More Heroes", HIGH, "typo; the unnumbered title is the first game"),
    "outlast": ("Outlast", HIGH, "exact title; the sequels are numbered"),
    "overwatch": ("Overwatch 2", HIGH, "the original Overwatch was shut down in 2022 and replaced by Overwatch 2"),
    "persona 3 reload": ("Persona 3 Reload", HIGH, "exact title"),
    "phasmaphobia": ("Phasmophobia", HIGH, "typo"),
    "plateup": ("PlateUp!", HIGH, "exact title"),
    "pragmata": ("Pragmata", HIGH, "exact title (Capcom)"),
    "rainbow 6 siege": ("Tom Clancy's Rainbow Six Siege", HIGH, "number written as 6"),
    "rainbow six siege": ("Tom Clancy's Rainbow Six Siege", HIGH, "short title"),
    "red dead": ("Red Dead Redemption 2", LOW, "series without a number; 51-100 h and finished fits RDR2 (RDR1 is shorter)"),
    "red dead redemeption 2": ("Red Dead Redemption 2", HIGH, "typo"),
    "red dead redemption 2": ("Red Dead Redemption 2", HIGH, "exact title"),
    "resident evil": ("Resident Evil Requiem", LOW,
                      "series without a number; hours don't single out an entry, so the most recent main entry"),
    "resident evil 2 remake": ("Resident Evil 2", HIGH, "the 2019 remake, titled Resident Evil 2"),
    "resident evil4": ("Resident Evil 4", HIGH, "missing space; the 2023 remake, titled Resident Evil 4"),
    "residents evil 1": ("Resident Evil", HIGH, "typo; the first game (HD remaster)"),
    "roblox": ("Roblox", HIGH, "exact title"),
    "rocket league": ("Rocket League", HIGH, "exact title"),
    "schedule 1": ("Schedule I", HIGH, "number written as 1"),
    "spider man": ("Marvel's Spider-Man 2", LOW, "series without a number; most recent main entry"),
    "spiderman 2": ("Marvel's Spider-Man 2", HIGH, "short title"),
    "split fiction": ("Split Fiction", HIGH, "exact title"),
    "the crew 3": ("The Crew Motorfest", LOW, "there is no 'The Crew 3'; Motorfest is the third game in the series"),
    "the last of us": ("The Last of Us Part I", LOW,
                       "the unnumbered title is the first game; Part I is its current version (the 2013 original "
                       "also had online Factions)"),
    "valorant": ("Valorant", HIGH, "exact title"),
    "woflenstien": ("Wolfenstein II: The New Colossus", LOW,
                    "typo and series without a number; 6-10 h finished doesn't single out an entry, so the most "
                    "recent main entry"),
    "zelda oot": ("The Legend of Zelda: Ocarina of Time", HIGH, "abbreviation"),
    "zelda totk": ("The Legend of Zelda: Tears of the Kingdom", HIGH, "abbreviation"),
}

# (respondent, raw name casefolded) -> (title, confidence, reason): series names whose most
# plausible entry depends on that respondent's hours and status
SERIES_BY_RESPONDENT: dict[tuple[str, str], tuple[str, str, str]] = {
    ("R03", "batman"): ("Batman: Arkham Knight", LOW,
                        "series without a number; 26-50 h finished fits the Arkham games; most recent main entry"),
    ("R16", "spider man"): ("Marvel's Spider-Man", LOW,
                            "series without a number; 26-50 h finished at 76-99% trophies fits the 2018 game, and "
                            "this respondent lists no sequel; the 2023 sequel fits too"),
}


# Titles whose plain name matches a wrong or empty entry (in the app's table or on RAWG): pinned to
# the right RAWG slug. Found by inspecting the candidates; recorded so the choice is visible.
SLUG_PINS: dict[str, tuple[str, str]] = {
    "Fortnite": ("fornite-battle-royale", "the plain 'Fortnite' entries have no genres; Battle Royale is the "
                                          "mode people mean by Fortnite (RAWG's slug has the typo)"),
    "Fall Guys": ("fall-guys", "the app's 'fall guys' row is an empty duplicate; the real entry is "
                               "Fall Guys: Ultimate Knockout"),
    "God of War": ("god-of-war-2", "the app's 'God Of War' row is tagged Simulation only; RAWG's god-of-war-2 is the "
                                   "2018 game"),
}

# IGDB names the RAWG entry differently: look its modes up by this IGDB slug instead
IGDB_SLUG: dict[str, str] = {
    "Fortnite": "fortnite",   # RAWG "Fortnite Battle Royale"; IGDB has one "Fortnite" entry for all modes
}

# Searched on RAWG (name and spelling variants), no matching game: left unmatched, so they are out of
# genre diversity and online share only (the app's rule for games without genres or modes)
NOT_FOUND: dict[str, str] = {
    "Burglin' Gnomes": "not on RAWG; the search returns unrelated games",
    "Mecha Chameleon": "not on RAWG under 'Mecha' or 'Meccha'; the search returns other chameleon games",
}


def decide(respondent: str, raw: str) -> tuple[str, str, str]:
    """(title to look up, confidence, reason) for one survey entry."""
    key = raw.strip().casefold()
    if (respondent, key) in SERIES_BY_RESPONDENT:
        return SERIES_BY_RESPONDENT[(respondent, key)]
    if key not in DECISIONS:
        raise KeyError(f"no decision for {raw!r}")
    return DECISIONS[key]
