alter table public.commanders add column profile jsonb;
alter table public.faction_leaders add column sex text check (sex in ('f', 'm'));

update public.faction_leaders set sex = 'f'
where name in ('Brenna Hale', 'Isaude Kerrow', 'Elowen Marsh', 'Sabine Orrel', 'Thessaly Rook', 'Veda Karn', 'Cassia Vell', 'Ysolde Fenn',
               'Livia Tarn', 'Anneke Voss', 'Maelis Brack', 'Neve Arden', 'Wynne Aldercott', 'Hildegard Moss', 'Ailsa Craig', 'Mairead Lochlan');
update public.faction_leaders set sex = 'm' where sex is null;
alter table public.faction_leaders alter column sex set not null;

create table public.commander_name_parts (
  id serial primary key,
  faction_slug text not null references public.factions (slug) on delete cascade,
  kind text not null check (kind in ('given_m', 'given_f', 'family')),
  value text not null,
  unique (faction_slug, kind, value)
);
alter table public.commander_name_parts enable row level security;

create table public.commander_bio_parts (
  id serial primary key,
  kind text not null check (kind in ('origin', 'event', 'quirk', 'epithet')),
  faction_slug text references public.factions (slug) on delete cascade,
  school text check (school in ('battleschool', 'university', 'rangers')),
  value text not null
);
alter table public.commander_bio_parts enable row level security;
create index commander_bio_parts_kind_idx on public.commander_bio_parts (kind, faction_slug, school);

insert into public.commander_name_parts (faction_slug, kind, value)
select f, k, v from (values
  ('kaldran', 'given_m', array['Osmund', 'Harl', 'Bertram', 'Conrad', 'Dietmar', 'Falk', 'Gunther', 'Helm', 'Ivar', 'Roland', 'Anselm', 'Wolfram']),
  ('kaldran', 'given_f', array['Adela', 'Brunhild', 'Gisela', 'Hedda', 'Irma', 'Mathilde', 'Odile', 'Thilde', 'Wilma', 'Ermengard', 'Kunigund', 'Sieglinde']),
  ('kaldran', 'family', array['Stonehelm', 'Ironwall', 'Hartmann', 'Brandt', 'Falkner', 'Gatewright', 'Holdfast', 'Towerman', 'Marchwall', 'Redkeep', 'Barrowgate', 'Wardlaw']),
  ('veyra', 'given_m', array['Aurel', 'Benedek', 'Cassian', 'Damien', 'Emeric', 'Florian', 'Gaspard', 'Jules', 'Lucien', 'Matthis', 'Octave', 'Silvan']),
  ('veyra', 'given_f', array['Alix', 'Berenice', 'Clemence', 'Delphine', 'Elise', 'Fleur', 'Genevieve', 'Isaure', 'Odalys', 'Rosalind', 'Solenne', 'Yvette']),
  ('veyra', 'family', array['Vellane', 'Chancel', 'Lacombe', 'Penhallow', 'Scriven', 'Margrave', 'Orlande', 'Ravel', 'Silvane', 'Tessier', 'Inkmoor', 'Sealwright']),
  ('dravos', 'given_m', array['Bjorn', 'Drogo', 'Gorm', 'Hakon', 'Ketil', 'Magnus', 'Rurik', 'Soren', 'Torben', 'Ulf', 'Vidar', 'Orm']),
  ('dravos', 'given_f', array['Astrid', 'Dagny', 'Freydis', 'Gudrun', 'Hilda', 'Ingrith', 'Ragna', 'Sigrun', 'Tove', 'Yrsa', 'Brynja', 'Solveig']),
  ('dravos', 'family', array['Blackforge', 'Cinder', 'Anvilson', 'Slagborn', 'Coalhand', 'Ironvein', 'Hammerfell', 'Emberly', 'Kilnman', 'Ashmark', 'Bellows', 'Flintmoor']),
  ('halcyr', 'given_m', array['Bayard', 'Gawain', 'Leofwin', 'Percy', 'Roderick', 'Tristan', 'Wilfred', 'Godwin', 'Edwin', 'Lancelin', 'Aubrey', 'Garrett']),
  ('halcyr', 'given_f', array['Aldith', 'Beatrix', 'Cecily', 'Eleanor', 'Gwenllian', 'Isabeau', 'Joanna', 'Rosamund', 'Sybil', 'Tamsin', 'Philippa', 'Lysette']),
  ('halcyr', 'family', array['Highsun', 'Downham', 'Swiftbrook', 'Harcourt', 'Lightfoot', 'Ridgeway', 'Spurrier', 'Stanhope', 'Wheeler', 'Windmere', 'Bridlewell', 'Saddler']),
  ('mereth', 'given_m', array['Alvise', 'Benedetto', 'Corrado', 'Domenico', 'Enzo', 'Fabrizio', 'Giacomo', 'Lorenzo', 'Matteo', 'Vittorio', 'Tommaso', 'Raffaele']),
  ('mereth', 'given_f', array['Alessia', 'Bianca', 'Caterina', 'Donata', 'Elisabetta', 'Fiora', 'Giulia', 'Ilaria', 'Lucrezia', 'Violetta', 'Margherita', 'Serafina']),
  ('mereth', 'family', array['Dellacorte', 'Calvari', 'Fiorenzi', 'Montalto', 'Morosan', 'Pellegrin', 'Rossetti', 'Salviati', 'Tessaro', 'Zanetti', 'Barozzi', 'Vendrame']),
  ('ostrand', 'given_m', array['Anders', 'Bram', 'Caelan', 'Dirk', 'Eamon', 'Fenn', 'Jarek', 'Lorcan', 'Niall', 'Pieter', 'Rory', 'Sjoerd']),
  ('ostrand', 'given_f', array['Aoife', 'Brigit', 'Deirdre', 'Eira', 'Greta', 'Maren', 'Nessa', 'Saoirse', 'Sunniva', 'Wenna', 'Marit', 'Orla']),
  ('ostrand', 'family', array['Saltmarsh', 'Ferrywick', 'Tidewell', 'Netherby', 'Driftwood', 'Reedmoor', 'Seaborne', 'Shoalman', 'Wavecrest', 'Lanternby', 'Pierwright', 'Kelpmoor']),
  ('thornwick', 'given_m', array['Alder', 'Beorn', 'Cuthbert', 'Elmer', 'Godfrey', 'Hob', 'Oswin', 'Rowan', 'Wat', 'Aldous', 'Fenwick', 'Tobias']),
  ('thornwick', 'given_f', array['Bryony', 'Hazel', 'Ivy', 'Linnet', 'Maud', 'Willow', 'Yarrow', 'Elspeth', 'Heather', 'Clover', 'Primrose', 'Sorrel']),
  ('thornwick', 'family', array['Oakenshaw', 'Fletcher', 'Greenwood', 'Hollin', 'Thorne', 'Woodward', 'Ashby', 'Bracken', 'Larkspur', 'Rootham', 'Mossgrove', 'Birchley']),
  ('brannoch', 'given_m', array['Angus', 'Callum', 'Duncan', 'Fingal', 'Gregor', 'Hamish', 'Lachlan', 'Murdo', 'Ruaridh', 'Torquil', 'Alasdair', 'Kenneth']),
  ('brannoch', 'given_f', array['Fiona', 'Isla', 'Katrin', 'Morag', 'Nairne', 'Sorcha', 'Una', 'Ailis', 'Mhairi', 'Effie', 'Gormla', 'Rhona']),
  ('brannoch', 'family', array['Dunmaglass', 'Glenroy', 'Craigmore', 'Ardnamurk', 'Balfern', 'Strathmoor', 'Kinloch', 'Tarbert', 'Lochbrae', 'Ravenscrag', 'Corriemuir', 'Glenfarg'])
) as t(f, k, a), unnest(t.a) as v;

insert into public.commander_bio_parts (kind, faction_slug, value) values
  ('origin', 'kaldran', $t$Born in the shadow of the Kaldrin curtain wall, a mason's {kid}.$t$),
  ('origin', 'kaldran', $t$Raised in a beacon tower on the northern march, among the signal-keepers.$t$),
  ('origin', 'kaldran', $t$The {kid} of a gate-warden, taught to close a gate before learning to read.$t$),
  ('origin', 'kaldran', $t$Grew up in the barracks of Kaldrin Keep, a soldier's orphan fed from the garrison kitchens.$t$),
  ('origin', 'kaldran', $t$Born in a border fort that changed hands twice before {s} could walk.$t$),
  ('origin', 'kaldran', $t$A cadet of the Warden-House, sent at twelve to learn the walls.$t$),
  ('origin', 'veyra', $t$Born in the Silver Chancery's copy-rooms, a scribe's {kid}.$t$),
  ('origin', 'veyra', $t$Raised in the archive vaults of Veyrmoor, reading by lamplight.$t$),
  ('origin', 'veyra', $t$The {kid} of a minor chancery clerk, taught to forge nothing and remember everything.$t$),
  ('origin', 'veyra', $t$Grew up in a courier house on the Great Road, carrying letters before {s} was tall enough for a saddle.$t$),
  ('origin', 'veyra', $t$Sent as a child to the Veyran school of law.$t$),
  ('origin', 'veyra', $t$A scholar's ward, raised among oaths and ledgers.$t$),
  ('origin', 'dravos', $t$Born beside the forges of Cinderhold, with soot in the cradle.$t$),
  ('origin', 'dravos', $t$A miner's {kid} from the northern ridge, deep underground by ten.$t$),
  ('origin', 'dravos', $t$Raised in the siege yards, handing nails to engine-wrights.$t$),
  ('origin', 'dravos', $t$The {kid} of a bellows-boy, taught that steel is the only honest argument.$t$),
  ('origin', 'dravos', $t$Grew up on the ash roads between the pits and the smelters.$t$),
  ('origin', 'dravos', $t$Apprenticed at nine to a Dravos armourer.$t$),
  ('origin', 'halcyr', $t$Born on the Sunlit Downs, in the saddle before {s} could walk.$t$),
  ('origin', 'halcyr', $t$A horse-breeder's {kid} from the downs, trusted with the fastest colt at eight.$t$),
  ('origin', 'halcyr', $t$Raised in the stables of Highsun Hold, where the road-riders trained.$t$),
  ('origin', 'halcyr', $t$The {kid} of a minor knight, schooled in the Dawn Oath.$t$),
  ('origin', 'halcyr', $t$Grew up riding the Great Road from the downs to the coast.$t$),
  ('origin', 'halcyr', $t$A squire at twelve and a courier at fourteen.$t$),
  ('origin', 'mereth', $t$Born in a dye-works on the Rosewater, hands stained to the wrist.$t$),
  ('origin', 'mereth', $t$A factor's {kid}, raised counting bales on the Merethport quays.$t$),
  ('origin', 'mereth', $t$The {kid} of a barge-master, familiar with every toll between the delta and the hills.$t$),
  ('origin', 'mereth', $t$Grew up in a counting-house, taught that every promise has a price.$t$),
  ('origin', 'mereth', $t$Raised in the madder fields above the river.$t$),
  ('origin', 'mereth', $t$Sold into a merchant house as a clerk and bought out within a year.$t$),
  ('origin', 'ostrand', $t$Born on a ferry in the delta, with the river for a cradle.$t$),
  ('origin', 'ostrand', $t$A fisher's {kid} from the reed villages, who could read the tide at six.$t$),
  ('origin', 'ostrand', $t$Raised in a lamp-tower on the coast, keeping the lights lit.$t$),
  ('origin', 'ostrand', $t$The {kid} of a ford-keeper, who knew every crossing by its sound.$t$),
  ('origin', 'ostrand', $t$Grew up among the net-menders of Tideholm.$t$),
  ('origin', 'ostrand', $t$Came to the delta as a refugee child and was taken in by a ferry crew.$t$),
  ('origin', 'thornwick', $t$Born in the deep forest, in a charcoal-burner's hut.$t$),
  ('origin', 'thornwick', $t$A forester's {kid}, set to count trees at five.$t$),
  ('origin', 'thornwick', $t$Raised among the bowyers of Greatoak.$t$),
  ('origin', 'thornwick', $t$The {kid} of a ranger of the boughs, taught to walk without breaking a twig.$t$),
  ('origin', 'thornwick', $t$Grew up in a granary-warden's house, and never went hungry in a famine.$t$),
  ('origin', 'thornwick', $t$Found as a foundling under an oak and raised by the whole village.$t$),
  ('origin', 'brannoch', $t$Born in a highland shieling, among sheep, stone and cousins.$t$),
  ('origin', 'brannoch', $t$A clan herder's {kid}, answering the horn at ten.$t$),
  ('origin', 'brannoch', $t$Raised at a pass-fort in the eastern hills.$t$),
  ('origin', 'brannoch', $t$The {kid} of a spearman who never came home from the Concord's wars.$t$),
  ('origin', 'brannoch', $t$Grew up at the moot-stones, listening to the elders argue.$t$),
  ('origin', 'brannoch', $t$A cattle-raider's {kid}, forgiven by the clan and put to work.$t$);

insert into public.commander_bio_parts (kind, school, value) values
  ('event', 'battleschool', $t$At sixteen {s} held a ford alone for a night against raiders.$t$),
  ('event', 'battleschool', $t$Survived a siege by eating the garrison's leather and refusing to surrender.$t$),
  ('event', 'battleschool', $t$Won {p} first command when every officer above {o} had fallen.$t$),
  ('event', 'battleschool', $t$Broke a charge that had already broken two other captains.$t$),
  ('event', 'battleschool', $t$Carried a wounded commander three leagues rather than leave {o} behind.$t$),
  ('event', 'battleschool', $t$Learned the shield-wall from a veteran who never spoke of the war.$t$),
  ('event', 'university', $t$Taught {self} accounting by keeping a besieged garrison's grain rolls.$t$),
  ('event', 'university', $t$Spent a winter in the archives and came out knowing every treaty by heart.$t$),
  ('event', 'university', $t$Once talked a captain out of burning a granary, and a district out of leaving.$t$),
  ('event', 'university', $t$Wrote a manual on supply wagons that three houses quietly copied.$t$),
  ('event', 'university', $t$Survived a plague year by rationing a city's bread to the ounce.$t$),
  ('event', 'university', $t$Tutored a lord's children and learned how lords think.$t$),
  ('event', 'rangers', $t$Spent a year alone in the border forests and came back knowing every game trail.$t$),
  ('event', 'rangers', $t$Guided a lost army out of the marsh and was never thanked.$t$),
  ('event', 'rangers', $t$Tracked a bandit band for forty days without being seen once.$t$),
  ('event', 'rangers', $t$Learned the roads by walking all of them, twice.$t$),
  ('event', 'rangers', $t$Once crossed a flooded ford at night by the sound of the water alone.$t$),
  ('event', 'rangers', $t$Left a village rather than see it burned, and has not slept indoors since.$t$);

insert into public.commander_bio_parts (kind, value) values
  ('quirk', $t$Never sits with {p} back to a door.$t$),
  ('quirk', $t$Keeps a notched stick for every promise kept.$t$),
  ('quirk', $t$Hums the same three bars before every battle.$t$),
  ('quirk', $t$Will not eat before the troops have eaten.$t$),
  ('quirk', $t$Writes a letter home every month and sends none.$t$),
  ('quirk', $t$Carries a lucky coin that has never once been lucky.$t$),
  ('quirk', $t$Names every horse after a former employer.$t$),
  ('quirk', $t$Speaks softly and expects to be obeyed anyway.$t$),
  ('quirk', $t$Counts the steps of every march.$t$),
  ('quirk', $t$Distrusts any map {s} did not walk.$t$),
  ('quirk', $t$Is always the last to sleep and the first awake.$t$),
  ('quirk', $t$Keeps a dried flower from {p} first battle tucked in {p} collar.$t$),
  ('quirk', $t$Laughs at the worst moments and has stopped apologising.$t$),
  ('quirk', $t$Cannot abide a dirty blade.$t$);

insert into public.commander_bio_parts (kind, school, value) values
  ('epithet', 'battleschool', 'the Bold'), ('epithet', 'battleschool', 'Shieldbreaker'), ('epithet', 'battleschool', 'the Unyielding'),
  ('epithet', 'battleschool', 'Ironhand'), ('epithet', 'battleschool', 'the Steady'), ('epithet', 'battleschool', 'Breaker of Lines'),
  ('epithet', 'battleschool', 'the Red'), ('epithet', 'battleschool', 'Stormbrow'), ('epithet', 'battleschool', 'the Grim'),
  ('epithet', 'university', 'the Reckoner'), ('epithet', 'university', 'the Learned'), ('epithet', 'university', 'Quillhand'),
  ('epithet', 'university', 'the Careful'), ('epithet', 'university', 'Keeper of Tallies'), ('epithet', 'university', 'the Lamplit'),
  ('epithet', 'university', 'Ledger-Eyed'), ('epithet', 'university', 'the Archivist'), ('epithet', 'university', 'Counter of Spears'),
  ('epithet', 'rangers', 'the Swift'), ('epithet', 'rangers', 'Pathfinder'), ('epithet', 'rangers', 'Hedge-Walker'),
  ('epithet', 'rangers', 'Quietfoot'), ('epithet', 'rangers', 'the Wary'), ('epithet', 'rangers', 'Far-Seer'),
  ('epithet', 'rangers', 'Trailwise'), ('epithet', 'rangers', 'the Unseen'), ('epithet', 'rangers', 'the Lean');

create function public.fill_pronouns(p_text text, p_sex text)
returns text
language sql
immutable
set search_path = ''
as $f$
  select case when p_sex = 'f' then
    replace(replace(replace(replace(replace(replace(p_text, '{kid}', 'daughter'), '{self}', 'herself'), '{S}', 'She'), '{s}', 'she'), '{p}', 'her'), '{o}', 'her')
  else
    replace(replace(replace(replace(replace(replace(p_text, '{kid}', 'son'), '{self}', 'himself'), '{S}', 'He'), '{s}', 'he'), '{p}', 'his'), '{o}', 'him')
  end
$f$;

create function public.commander_identity(p_game_id int, p_player_id int)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_slug text;
  v_sex text;
  v_given text;
  v_family text;
  v_name text;
  v_try int := 0;
begin
  select faction_slug into v_slug from public.game_players where id = p_player_id;
  loop
    v_sex := case when random() < 0.4 then 'f' else 'm' end;
    select value into v_given from public.commander_name_parts
      where faction_slug = v_slug and kind = 'given_' || v_sex order by random() limit 1;
    select value into v_family from public.commander_name_parts
      where faction_slug = v_slug and kind = 'family' order by random() limit 1;
    v_name := v_given || ' ' || v_family;
    v_try := v_try + 1;
    exit when v_try > 100 or v_given is null or v_family is null
      or not exists (select 1 from public.commanders c where c.game_id = p_game_id and c.name = v_name);
  end loop;
  if v_given is null or v_family is null then
    v_name := public.random_commander_name(p_game_id);
  end if;
  return jsonb_build_object('name', v_name, 'sex', v_sex);
end;
$f$;

create function public.commander_profile(p_player_id int, p_school text, p_role text, p_sex text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare
  v_slug text;
  v_age int;
  v_hair int;
  v_beard int;
  v_scar int;
  v_epithet text;
  v_origin text;
  v_event text;
  v_quirk text;
begin
  select faction_slug into v_slug from public.game_players where id = p_player_id;
  v_age := case when p_role = 'king' then 42 + floor(random() * 21)::int else 20 + floor(random() * 36)::int end;
  v_hair := case when p_sex = 'f'
    then (array[1, 2, 3, 4, 4, 5, 5, 6, 8])[1 + floor(random() * 9)::int]
    else (array[0, 1, 1, 2, 2, 3, 4, 5, 6, 7, 8])[1 + floor(random() * 11)::int] end;
  v_beard := case when p_sex = 'f' then 0 else floor(random() * 6)::int end;
  v_scar := case when random() < (case when p_school = 'battleschool' then 0.45 else 0.22 end) then 1 + floor(random() * 3)::int else 0 end;

  select value into v_origin from public.commander_bio_parts where kind = 'origin' and faction_slug = v_slug order by random() limit 1;
  select value into v_event from public.commander_bio_parts where kind = 'event' and school = p_school order by random() limit 1;
  select value into v_quirk from public.commander_bio_parts where kind = 'quirk' order by random() limit 1;
  if p_role = 'king' or random() < 0.7 then
    select value into v_epithet from public.commander_bio_parts where kind = 'epithet' and school = p_school order by random() limit 1;
  end if;

  return jsonb_build_object(
    'sex', p_sex,
    'age', v_age,
    'epithet', v_epithet,
    'bio', public.fill_pronouns(concat_ws(' ', v_origin, v_event, v_quirk), p_sex),
    'look', jsonb_build_object(
      'skin', floor(random() * 6)::int,
      'face', floor(random() * 4)::int,
      'hair', v_hair,
      'hairc', floor(random() * 7)::int,
      'beard', v_beard,
      'eyes', floor(random() * 5)::int,
      'brow', floor(random() * 4)::int,
      'nose', floor(random() * 3)::int,
      'mouth', floor(random() * 3)::int,
      'scar', v_scar
    )
  );
end;
$f$;

revoke execute on function public.fill_pronouns(text, text) from public, anon, authenticated;
revoke execute on function public.commander_identity(int, int) from public, anon, authenticated;
revoke execute on function public.commander_profile(int, text, text, text) from public, anon, authenticated;

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    '  v_pick text;' || chr(10) || 'begin',
    '  v_pick text;' || chr(10) || '  v_ident jsonb;' || chr(10) || 'begin',
    '  v_pick := v_school_abilities[1 + floor(random() * 3)::int];',
    '  v_pick := v_school_abilities[1 + floor(random() * 3)::int];' || chr(10) || '  v_ident := public.commander_identity(p_game_id, p_player_id);',
    '(game_id, owner_player_id, name, school, role, current_territory_id, created_tick)',
    '(game_id, owner_player_id, name, school, role, current_territory_id, created_tick, profile)',
    'public.random_commander_name(p_game_id), p_school, p_role, p_territory_id, p_tick)',
    'v_ident ->> ''name'', p_school, p_role, p_territory_id, p_tick, public.commander_profile(p_player_id, p_school, p_role, v_ident ->> ''sex''))'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'create_commander' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'create_commander patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '''name'', c.name, ''school'', c.school,',
    '''name'', c.name, ''profile'', c.profile, ''school'', c.school,'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'get_game_view' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'get_game_view patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;

  v_pairs := array[
    '  v_lname text;',
    '  v_lname text;' || chr(10) || '  v_lead public.faction_leaders%rowtype;',
    '      select fl.name into v_lname from public.faction_leaders fl where fl.faction_slug = v_p.faction_slug and fl.ord = v_i;' || chr(10)
      || '      if v_lname is not null then' || chr(10)
      || '        update public.commanders set name = v_lname where id = v_cid;' || chr(10)
      || '      end if;',
    '      select * into v_lead from public.faction_leaders fl where fl.faction_slug = v_p.faction_slug and fl.ord = v_i;' || chr(10)
      || '      if v_lead.name is not null then' || chr(10)
      || '        update public.commanders set name = v_lead.name,' || chr(10)
      || '          profile = public.commander_profile(v_p.id, v_school, case when v_i = 1 then ''king'' else ''commander'' end, v_lead.sex)' || chr(10)
      || '            || jsonb_build_object(''epithet'', v_lead.title, ''bio'', v_lead.bio)' || chr(10)
      || '        where id = v_cid;' || chr(10)
      || '      end if;'
  ];
  select pg_get_functiondef(p.oid) into v_def from pg_proc p where p.proname = 'finalize_start' and p.pronamespace = 'public'::regnamespace;
  v_new := v_def;
  for i in 1 .. array_length(v_pairs, 1) / 2 loop
    if position(v_pairs[2 * i - 1] in v_new) = 0 then
      raise exception 'finalize_start patch % did not match', i;
    end if;
    v_new := replace(v_new, v_pairs[2 * i - 1], v_pairs[2 * i]);
  end loop;
  execute v_new;
end;
$patch$;

update public.commanders c
set profile = public.commander_profile(
  c.owner_player_id, c.school, c.role,
  case when split_part(c.name, ' ', 1) = any (array['Isolde', 'Maren', 'Brenna', 'Cordelia', 'Daria', 'Elara', 'Freya', 'Greta', 'Helena', 'Ingrid', 'Jocelyn', 'Katarin', 'Mirelle',
    'Elowen', 'Isaude', 'Sabine', 'Thessaly', 'Veda', 'Cassia', 'Ysolde', 'Livia', 'Anneke', 'Maelis', 'Neve', 'Wynne', 'Hildegard', 'Ailsa', 'Mairead']) then 'f' else 'm' end)
where c.profile is null;
