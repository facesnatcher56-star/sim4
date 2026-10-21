"""Owner rule 43 (no magic events): the verdict table of docs/MAGIC_EVENTS_AUDIT.md and the one-off data patch that applies the 'removed' verdicts.
   python tools/magic_audit.py apply   -> sets weight 0 + "removed" on the removed storyteller cards and rate 0 on the disabled incidents (idempotent)
   python tools/magic_audit.py doc     -> writes docs/MAGIC_EVENTS_AUDIT.md from the data and the verdicts below
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# storyteller cards removed (weight 0): id -> why
REMOVED = {
    'found_money': 'coins from nowhere: no culprit, no loss for anyone',
    'lottery_win': 'a win with no ticket: the real lottery (BankGamble) pays real tickets',
    'inheritance_card': 'kills a townie relative to pay out: an inheritance must come from a real death and a real will',
    'long_lost_family': 'creates a relative from nothing: needs an existing person in the family tree with a reason to look you up',
    'identity_theft_card': 'money drained with no culprit and no case: real fraud (CrimeFraud) replaces it',
    'layoff_card': 'closes a job with no employer, economy or plant state behind it: real layoffs come from MarketWork and the works events',
    'small_claims_card': 'a damaged fence with no fence and no damage',
    'midlife_card': 'a timer at 30 to 31, not age and life state',
    'stranger_arrives': 'creates a townie from nothing: needs a vacant home and a mover',
    'secret_out': 'a leak with no real secret: needs the real secret and gossip system to roll it',
    'anonymous_letter': 'text only: nobody wrote it',
    'old_flame': 'needs a real ex in the relationship history who has a reason to return',
    'rival_next_door': 'creates a townie from nothing',
    'mysterious_inheritance': 'coins from nowhere',
    'pet_on_doorstep': 'creates a pet from nothing',
    'headhunter': 'a job offer from nowhere: the job board and the career system make real offers',
    'contest': 'prize money from nowhere',
    'lost_wallet': 'coins from nowhere: needs a real townie who lost their own money',
    'work_power_struggle': 'no real managers: pay or stress with no actor',
    'audit': 'no tax cause: a real audit needs a real tax record',
    'gold_digger': 'creates a townie from nothing',
    'mayor_scandal': 'a scandal with no actor: the city mood moves with real events only',
    'scandal_hall': 'a scandal with no actor',
    'city_hall_rally': 'a rally with no actor',
    'town_fair': 'a fair with no organiser: holidays and real events cover it',
    'shop_robbery': 'coins removed from a townie with no culprit: the real robbery rolls cover it',
    'celebrity_cafe': 'text only',
    'protest': 'text only',
    'pollution_scare': 'text only: no source of pollution',
    'smuggling_rumour': 'text only',
    'port_strike': 'text only: no port, no workers',
    'street_party': 'text only: no host',
    'vigilante': 'text only: the real vigilante roll is in CrimeRevenge',
    'wrong_arrest': 'text only: a wrongful arrest must come from the evidence system',
    'insurance_probe': 'text only: no claim',
    'neighbours_quarrel': 'text only: no neighbours acting',
    'factory_closure': 'text only: closures come from the works events',
    'factory_layoffs': 'lays townies off with no employer state',
    'petty_crime_spree': 'removes coins from a townie with no culprit',
    'lawsuit': 'coins removed with no case',
    'power_cut_block': 'an outage with no cause: real outages come from storms, overload and faults',
    'road_works': 'works with no council project',
    'arc_feud': 'stages are story text with no real actor',
    'arc_stalker': 'stages are story text with no real actor',
    'arc_rising_criminal': 'stages are story text with no real actor',
    'arc_family_secret': 'stages are story text with no real actor',
    'arc_business': 'stages are story text: a shop closes by decree, not by money',
    'arc_town_crisis': 'stages are story text with no real sickness',
    'arc_triangle': 'stages are story text with no real actor',
    'arc_missing': 'stages are story text with no real person gone',
}

# incidents whose yearly rate is set to 0 (no outcome without a real cause): id -> (file, why)
DISABLED_INCIDENTS = {
    'found_money': ('00_framework_examples.json', 'coins from nowhere (the coat coins)'),
    'lottery_win': ('07b_chaos_more.json', 'a win with no ticket'),
    'inheritance': ('07b_chaos_more.json', 'kills a townie relative to pay out'),
    'long_lost_family': ('07b_chaos_more.json', 'creates a relative from nothing'),
    'identity_theft': ('07b_chaos_more.json', 'money drained with no culprit and no case'),
    'midlife_crisis': ('07b_chaos_more.json', 'a timer, not a life state'),
    'layoff': ('07b_chaos_more.json', 'closes a job with no employer state'),
    'small_claims': ('09_justice.json', 'a claim with no damage'),
}

# the cards that stay: id -> (real cause, checks that can stop it, verdict)
CARD_OK = {
    'appliance_breaks': ('wear of a real appliance (incident appliance_breakdown)', 'repair skill, quality, insurance', 'ODDS TILT'),
    'pests': ('dirt and food left out (roach_infestation)', 'cleanliness', 'ODDS TILT'),
    'overflow': ('use of a real toilet (toilet_overflow)', 'repair, plumbing condition', 'ODDS TILT'),
    'pipe': ('an ageing pipe (burst_pipe)', 'repair, pipe condition', 'ODDS TILT'),
    'burglary_card': ('a real burglar from the townies (burglary)', 'locks, alarm, dog, lights, awake people, police', 'ODDS TILT'),
    'street_burglary': ('a real burglar (burglary)', 'same', 'ODDS TILT'),
    'eviction_scare': ('unpaid bills and a repossession (eviction_notice; solo play uses the landlord)', 'pay the bills', 'ODDS TILT'),
    'vandalism_card': ('a real offender (vandalism)', 'patrols, lights, caught on scene', 'ODDS TILT'),
    'cold_card': ('exposure and contact (catch_cold)', 'hygiene, flu shot, rest', 'ODDS TILT'),
    'robbery_card': ('a real mugger (street_robbery)', 'patrols, being indoors, carrying little', 'ODDS TILT'),
    'fire_nearby': ('a real kitchen fire (kitchen_fire)', 'extinguisher, alarm, brigade', 'ODDS TILT'),
    'crash_avenue': ('real traffic (traffic_hit)', 'crossings, lights', 'ODDS TILT'),
    'workplace_accident': ('a risky job (workplace_injury)', 'safety, skill', 'ODDS TILT'),
    'neighbour_favour': ('a real neighbour asks (friendship only, no money, no outcome)', 'the player says no', 'OK'),
    'neighbourhood_watch': ('lowers burglary heat: an odds change only', 'n/a', 'ODDS TILT'),
    'cycle_crime_wave': ('an era that multiplies real crime rolls', 'the real checks still apply', 'OK (era)'),
    'cycle_flu_season': ('an era that multiplies real flu rolls', 'the real checks still apply', 'OK (era)'),
    'cycle_boom': ('an era of the market economy', 'n/a', 'OK (era)'),
    'cycle_bust': ('an era of the market economy', 'n/a', 'OK (era)'),
    'cycle_heat_wave': ('a weather era', 'n/a', 'OK (era)'),
    'cycle_cold_snap': ('a weather era', 'n/a', 'OK (era)'),
    'cycle_election_scandal': ('an era of the city election', 'n/a', 'OK (era)'),
}

NEEDS_SYSTEM = [
    ('Newcomers (stranger_arrives, rival_next_door, gold_digger, ask_to_stay)', 'a mover system: a townie arrives only when a home is vacant and a reason exists (work, family, an eviction elsewhere).'),
    ('Real secrets that leak (secret_out)', 'RelationshipKnowledge has secrets and gossip; a leak roll per secret (who knows, who is angry, who talks) would replace the card.'),
    ('Old flame (old_flame)', 'needs an ex in the relationship history with a reason to return (a breakup, a move, a death).'),
    ('Lost wallet, small money finds', 'a real townie who loses their own coins; the finder gets a real reward or keeps a real loss.'),
    ('Story arcs (all eight)', 'each stage needs a real actor and a real consequence: a feud from neighbour disputes, a stalker from a real obsessed townie, a missing person from a real disappearance, a business from real takings.'),
    ('Tax audits, lawsuits, insurance probes', 'a record of declared income and claims; the audit rolls from the records.'),
    ('Power cuts, road works, pollution, strikes', 'already real in Utilities, CityPlan and WorksEvents; the cards were duplicates and are gone.'),
]


def apply():
    p = os.path.join(ROOT, 'data', 'storyteller_cards.json')
    lines = open(p, encoding='utf-8-sig', newline='').read().split('\n')
    n = 0
    for i, ln in enumerate(lines):
        m = re.match(r'^(\s+)"([a-z_0-9]+)": \{"title"', ln)
        if not m or m.group(2) not in REMOVED:
            continue
        ln2 = re.sub(r'"weight": [0-9.]+', '"weight": 0', ln)
        if '"removed"' not in ln2:
            ln2 = re.sub(r'\}(,?)$', lambda mm: ', "removed": %s}%s' % (json.dumps(REMOVED[m.group(2)]), mm.group(1)), ln2)
        if ln2 != ln:
            lines[i] = ln2
            n += 1
    open(p, 'w', encoding='utf-8', newline='').write('\n'.join(lines))
    json.loads(open(p, encoding='utf-8').read())
    for iid, (fn, why) in DISABLED_INCIDENTS.items():
        fp = os.path.join(ROOT, 'data', 'incidents', fn)
        text = open(fp, encoding='utf-8-sig', newline='').read()
        m = re.search(r'("%s"\s*:\s*\{)' % re.escape(iid), text[text.index('"incidents"'):])
        start = text.index('"incidents"') + m.start()
        r = re.compile(r'"base_rate_per_year"\s*:\s*([0-9.eE+-]+)').search(text, start)
        if r and float(r.group(1)) != 0.0:
            text = text[:r.start(1)] + '0' + text[r.end(1):]
            open(fp, 'w', encoding='utf-8', newline='').write(text)
            json.loads(text)
    print('cards patched:', n)


def doc():
    cards = json.load(open(os.path.join(ROOT, 'data', 'storyteller_cards.json'), encoding='utf-8-sig'))['cards']
    out = ['# Magic events audit (owner rule 43)', '',
           'Rule: nothing that touches a person happens because the game said so. Every event needs a real cause (someone or something physically able to do it), the conditions that make it possible and the checks that can stop it. The storyteller may only tilt the odds of a real cause (it never creates an outcome). Nothing warns the player of what is coming; things are explained afterwards (task 44).', '',
           'Verdicts: **OK** = already has a real cause and checks. **ODDS TILT** = the card now only raises the odds of the incident\'s own roll. **REMOVED** = weight 0 / rate 0, because no real cause exists. Generated by `tools/magic_audit.py doc` from the data.', '',
           '## What changed in code', '',
           '- `StorytellerTilt`: an incident card adds a silent odds multiplier (small x6 for 2 days, medium x10 for 3, big x15 for 4; `data/storyteller.json` `tilt`) for ONE subject; `IncidentChecks._roll` multiplies the real roll by it, so the conditions, risk and prevention of the incident still run. No text, no toast.',
           '- Warnings are off: `data/incidents.json` `config.warnings` false (no lead-time warnings such as "feels queasy" or the heart attack warned 12 hours ahead) and `data/storyteller.json` `foreshadow_signs` false (no storyteller signs).',
           '- The murder ladder no longer warns the player: no "glaring" prompt, no "Step in" prompt, no countdown (`data/justice.json` `murder.player_prompts` false). The whisper gossip between townies stays: it is something people really say.',
           '- Murder and the serial killer need physical access (`CrimeIntrusion`, `data/justice.json` `intrusion`): both people in the same place, or the culprit gets in past the home\'s security against their determination (approach, entry, reach). Failed attempts leave a trace (an alarm that rang, a chronicle line), never a warning.', '',
           '## Storyteller cards', '', '| Card | Real cause | Checks | Verdict |', '|---|---|---|---|']
    for cid, c in cards.items():
        if cid in REMOVED:
            out.append('| %s (%s) | none: %s | - | **REMOVED** |' % (cid, c.get('title', ''), REMOVED[cid]))
        elif cid in CARD_OK:
            cause, checks, verdict = CARD_OK[cid]
            out.append('| %s (%s) | %s | %s | %s |' % (cid, c.get('title', ''), cause, checks, verdict))
        else:
            out.append('| %s (%s) | unreviewed | - | check |' % (cid, c.get('title', '')))
    out += ['', '## Incidents (data/incidents/*.json)', '',
            'Incidents with conditions that name a real cause (a buff from an activity, an object, the weather, the season, overdue bills, a job) are **OK**: acc_* accidents come from activities, fires from stoves and candles, disasters from weather and the season, crime from real offenders, illness from exposure. The ones below had no real cause and are **REMOVED** (yearly rate 0):', '',
            '| Incident | Why |', '|---|---|']
    for iid, (fn, why) in DISABLED_INCIDENTS.items():
        out.append('| %s (%s) | %s |' % (iid, fn, why))
    out += ['', 'Statistical townie outcomes for people far from the player are fine (that is the tier system); anything that reaches the player runs in full.', '',
            '## Needs a new system (for the owner to decide)', '']
    for title, why in NEEDS_SYSTEM:
        out.append('- **%s**: %s' % (title, why))
    open(os.path.join(ROOT, 'docs', 'MAGIC_EVENTS_AUDIT.md'), 'w', encoding='utf-8', newline='').write('\n'.join(out) + '\n')
    print('doc written')


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == 'apply':
        apply()
    elif len(sys.argv) > 1 and sys.argv[1] == 'doc':
        doc()
