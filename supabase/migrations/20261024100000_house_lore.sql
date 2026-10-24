alter table public.factions
  add column motto text,
  add column seat text,
  add column blurb text,
  add column history text,
  add column rival text references public.factions (slug),
  add column known_for text;

create table public.faction_leaders (
  faction_slug text not null references public.factions (slug) on delete cascade,
  ord int not null check (ord between 1 and 4),
  name text not null,
  title text not null,
  bio text not null,
  primary key (faction_slug, ord)
);

alter table public.faction_leaders enable row level security;

create policy "faction leaders are readable by everyone"
  on public.faction_leaders for select to anon, authenticated
  using (true);

update public.factions set
  motto = $t$We Were the Wall.$t$,
  seat = $t$Kaldrin Keep$t$,
  blurb = $t$The old Wardens of the Throne. Castle-builders who have never forgiven themselves for the Hollow Year.$t$,
  history = $t$Under the Concord the Kaldrans held the Throne's own garrison. Their charge was the capital and the first leagues of every road out of it, and their towers are still the tallest in the realm.$t$ || chr(10) || chr(10) || $t$When Emperor Aldous died without naming an heir, the Warden-Marshal shut the gates of Kaldrin Keep and held the capital for nine months against every house that came for the seals. No heir came. The gates were opened only when the granaries were empty. The Kaldrans carry the guilt of that winter and the pride of having held, and they will not be the first to open a gate again.$t$,
  rival = 'veyra',
  known_for = $t$Strong walls and watchtowers$t$
where slug = 'kaldran';

update public.factions set
  motto = $t$What Is Written Is Kept.$t$,
  seat = $t$Veyrmoor, the Silver Chancery$t$,
  blurb = $t$Chancellors and scribes of the old Throne. They keep the archives, and the memory of every oath.$t$,
  history = $t$The Veyrans ran the Chancery: they drafted every charter, kept the seal-matrices and filed every castle's title. A castle belonged to whoever held a charter in the Chancery's ink, and for four hundred years no one doubted it.$t$ || chr(10) || chr(10) || $t$The Chancery burned in the week the Emperor died. Veyra says thieves did it. Other houses say Veyra burned a will that named someone else. The house answers neither charge and has spent the sixty years since keeping a ledger of every promise made in the realm, and of who broke it. A Veyran alliance is hard to win and harder to leave.$t$,
  rival = 'kaldran',
  known_for = $t$Alliances, learning and long memories$t$
where slug = 'veyra';

update public.factions set
  motto = $t$Strike While It Glows.$t$,
  seat = $t$Cinderhold$t$,
  blurb = $t$Ironmasters of the northern ridge. Their forges armed the Concord, and now they arm themselves.$t$,
  history = $t$Dravos holds the iron ridges and the passes between them. Every soldier of the Concord wore Dravos steel, and the house grew rich and grim on the work: black from the soot, orange from the forge-glow.$t$ || chr(10) || chr(10) || $t$After the Hollow Year the forges did not stop. Dravos sold blades to every side until a Dravos-made siege engine broke a Dravos-held wall, and the house decided that if everyone was going to be armed, it would be best armed. It has no use for ceremony and no patience for houses that fight without enough steel.$t$,
  rival = 'halcyr',
  known_for = $t$Arms, siege engines and heavy infantry$t$
where slug = 'dravos';

update public.factions set
  motto = $t$First Light, First Blow.$t$,
  seat = $t$Highsun Hold$t$,
  blurb = $t$Horse-lords of the high downs. Fast, proud, and impatient with anyone who walks.$t$,
  history = $t$The Sunlit Downs breed the best horses in the Aldermark, and Halcyr bred the riders to match. Under the Concord they were the road-riders: the Throne's orders, tax-wagons and armies all moved at the speed Halcyr allowed, and the Great Roads were safe from the downs to the coast.$t$ || chr(10) || chr(10) || $t$They kept the roads open for sixty years after the Hollow Year, and then began charging for it. The Dawn Oath, which binds a Halcyran knight to strike first and never from behind, is the most admired code in the realm and the reason other houses build their castles with their gates facing away from the downs.$t$,
  rival = 'dravos',
  known_for = $t$Fast marches and stables$t$
where slug = 'halcyr';

update public.factions set
  motto = $t$Everything Has a Price.$t$,
  seat = $t$Merethport on the Rosewater$t$,
  blurb = $t$Dye-merchants and bankers of the river cities. Their gold buys what their swords cannot.$t$,
  history = $t$Mereth's purple comes from the shell-beds of the Rosewater delta and its rose from madder fields no other house is allowed to plant. The dyes made the first fortune; lending the Throne money for its wars made the second.$t$ || chr(10) || chr(10) || $t$When the Throne fell, Mereth called in every debt it held, from every house, on the same morning. Some castles changed hands that week without a single arrow shot. The house fights as it trades: it hires the best captains, pays on the day, and remembers exactly what each ally still owes.$t$,
  rival = 'ostrand',
  known_for = $t$Gold and hired captains$t$
where slug = 'mereth';

update public.factions set
  motto = $t$The Tide Returns.$t$,
  seat = $t$Tideholm$t$,
  blurb = $t$Ferrymen and fishers of the delta coast. They know every ford, and when the river will rise.$t$,
  history = $t$The delta has no bridges. For four hundred years every army, caravan and tax-collector crossed it on Ostrand ferries and Ostrand fords, and the house learned to read the river the way other houses read a ledger.$t$ || chr(10) || chr(10) || $t$After the Hollow Year Ostrand began to open and close the crossings by tide-table. A ford that is safe in spring can be a drowned road by midsummer, and only Ostrand knows which. They are patient to the point of insult, lose a good many first battles, and have yet to lose a war they chose to fight.$t$,
  rival = 'mereth',
  known_for = $t$River crossings and coastal levies$t$
where slug = 'ostrand';

update public.factions set
  motto = $t$Deep Roots.$t$,
  seat = $t$Greatoak$t$,
  blurb = $t$Foresters and bowmen of the old woods. They do not win quickly, but they do not leave.$t$,
  history = $t$Thornwick held the Concord's forests: the timber for its ships, the bows for its armies and the rights to every tree between the downs and the coast. The house measures time in rings, not years.$t$ || chr(10) || chr(10) || $t$When the Throne fell, Thornwick pulled back from the open country, gave up its edge castles and fought only where the trees began. The Long Bough, as the strategy is called, loses ground for a decade and then holds it for a century. No Thornwick garrison has starved in a siege since the Hollow Year, and the house plants an oak for every castle it keeps.$t$,
  rival = 'brannoch',
  known_for = $t$Scouts, bowmen and patient defence$t$
where slug = 'thornwick';

update public.factions set
  motto = $t$Many Spears.$t$,
  seat = $t$Brannoch Crag$t$,
  blurb = $t$Hill clans who answer the horn. Every herder is a soldier, and every soldier a cousin.$t$,
  history = $t$The eastern hills grow little but sheep, stone and sons. The Concord taxed Brannoch in men rather than coin, and for four hundred years a levy of Brannoch spears stood in every army the Throne raised.$t$ || chr(10) || chr(10) || $t$After the Hollow Year the clans stopped sending their sons away and kept them. A Brannoch king is chosen by the moot, not born, and a thousand spears can gather from a hundred farms before a beacon burns down. They are rich in men, poor in gold, and suspicious of any house that counts a soldier's worth in coin.$t$,
  rival = 'thornwick',
  known_for = $t$Large levies and cheap recruits$t$
where slug = 'brannoch';

insert into public.faction_leaders (faction_slug, ord, name, title, bio) values
  ('kaldran', 1, 'Osric Kaldran', 'Warden-King, the Shut Gate', $t$Grandson of the last Warden-Marshal. Raised on the story of the shut gates, and has never ordered a retreat.$t$),
  ('kaldran', 2, 'Brenna Hale', 'Keeper of the Ladder', $t$Has broken forty sieges from the inside, and trusts a wall more than a promise.$t$),
  ('kaldran', 3, 'Marek Dunholt', 'the Mason', $t$Rebuilt the Kaldrin curtain wall stone by stone after the famine winter. Reads a fortress like a ledger.$t$),
  ('kaldran', 4, 'Isaude Kerrow', 'Lamp of the Watch', $t$Commands the beacon towers. Nothing crosses the border without her knowing by dusk.$t$),

  ('veyra', 1, 'Lucan Veyr', 'Chancellor-King, the Quiet Pen', $t$Signs nothing in haste. Rumoured to have read the Emperor's last letter, and to have burned it.$t$),
  ('veyra', 2, 'Elowen Marsh', 'Keeper of Oaths', $t$Remembers every treaty and who broke it. Her ledgers make would-be traitors think twice.$t$),
  ('veyra', 3, 'Hadwin Corr', 'the Cartographer', $t$Mapped the Great Roads from the old Road-Warden logs. Knows where every crossroads lies and who built it.$t$),
  ('veyra', 4, 'Sabine Orrel', 'Silver Courier', $t$Runs the house's letter-riders. Her messages arrive before the armies they warn of.$t$),

  ('dravos', 1, 'Garrick Dravos', 'Iron-King, the Smith-King', $t$Still works the anvil one morning a week. Says a king who cannot make a nail cannot judge a sword.$t$),
  ('dravos', 2, 'Thessaly Rook', 'Master of the Siege Yards', $t$Names every engine she builds for a wall it has broken. The list is long.$t$),
  ('dravos', 3, 'Brogan Ashe', 'the Hammer-Hand', $t$Leads the Cinder Guard, mailed infantry who march in step to the forge-bell.$t$),
  ('dravos', 4, 'Veda Karn', 'Quartermaster of Cinderhold', $t$Nothing leaves the forges without a tally. Her wagons always arrive.$t$),

  ('halcyr', 1, 'Aurelian Halcyr', 'Dawn-King, the Bright Banner', $t$Rides at the head of the host. Has been unhorsed exactly once, by a bridge.$t$),
  ('halcyr', 2, 'Cassia Vell', 'Gallop-Marshal', $t$Can march an army half again as far in a day as anyone else will believe.$t$),
  ('halcyr', 3, 'Peregrine Lowe', 'the Courier-Knight', $t$Leads the road-riders who patrol the Great Roads and ride down bandits and tollkeepers alike.$t$),
  ('halcyr', 4, 'Ysolde Fenn', 'Lady of the Standard', $t$Carries the sun banner. Her presence on a field has turned two lost battles.$t$),

  ('mereth', 1, 'Cosimo Mereth', 'Prince-Merchant, the Open Hand', $t$Never raises his voice. Has bought three castles and one war.$t$),
  ('mereth', 2, 'Livia Tarn', 'Mistress of the Mint', $t$Counts every coin twice and every soldier once.$t$),
  ('mereth', 3, 'Dorian Pell', 'the Silk Captain', $t$Mercenary captain on retainer. Loyal to the contract, which he wrote.$t$),
  ('mereth', 4, 'Anneke Voss', 'Rosewater Factor', $t$Runs the barge fleets. If goods exist, she knows what they cost to move.$t$),

  ('ostrand', 1, 'Joran Ostrand', 'Tide-King, the Patient Shore', $t$Has lost every first battle and won every war. Says the sea teaches that.$t$),
  ('ostrand', 2, 'Maelis Brack', 'Ford-Warden', $t$Knows a safe crossing wherever the river runs, and a drowned army wherever it does not.$t$),
  ('ostrand', 3, 'Torvald Seam', 'Lamplighter', $t$Keeper of the coast lights. Ships and armies both arrive where he lets them.$t$),
  ('ostrand', 4, 'Neve Arden', 'the Net-Mother', $t$Leads the fisher levies. They appear out of the reeds, and so do their arrows.$t$),

  ('thornwick', 1, 'Edric Thornwick', 'Warden-King, the Green Oak', $t$Planted an acorn on the day of his crowning. Says he will know the war is won when it fruits.$t$),
  ('thornwick', 2, 'Wynne Aldercott', 'Hawk of the Boughs', $t$Chief of the rangers. Has never been seen by an enemy she did not intend to be seen by.$t$),
  ('thornwick', 3, 'Piers Wren', 'Master of the Long Bow', $t$Teaches that one arrow shot patiently is worth ten shot in anger.$t$),
  ('thornwick', 4, 'Hildegard Moss', 'the Root-Mother', $t$Steward of the granaries. No Thornwick garrison has starved in a siege in sixty years.$t$),

  ('brannoch', 1, 'Bran Brannoch', 'Clan-King, the Horn-Bearer', $t$Chosen by the moot, not born to it. Calls the hills with a horn his grandfather carried.$t$),
  ('brannoch', 2, 'Ailsa Craig', 'the Cattle-Queen', $t$Can raise a thousand spears from a hundred farms before the beacon burns out.$t$),
  ('brannoch', 3, 'Fergus Bale', 'Pass-Warden', $t$Holds the high pass with a hundred men. Has told the story so often it is mostly true.$t$),
  ('brannoch', 4, 'Mairead Lochlan', 'the Cairn-Mother', $t$Buries every fallen spearman under a cairn and calls the names at each muster.$t$);

do $patch$
declare
  v_def text;
  v_new text;
  v_pairs text[];
  i int;
begin
  v_pairs := array[
    '  v_school text;',
    '  v_school text;' || chr(10) || '  v_cid int;' || chr(10) || '  v_lname text;',
    '      perform public.create_commander(',
    '      v_cid := public.create_commander(',
    '        v_p.capital_territory_id, 0' || chr(10) || '      );',
    '        v_p.capital_territory_id, 0' || chr(10) || '      );' || chr(10)
    || '      select fl.name into v_lname from public.faction_leaders fl where fl.faction_slug = v_p.faction_slug and fl.ord = v_i;' || chr(10)
    || '      if v_lname is not null then' || chr(10)
    || '        update public.commanders set name = v_lname where id = v_cid;' || chr(10)
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
