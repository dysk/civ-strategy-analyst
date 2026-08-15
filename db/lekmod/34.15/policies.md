# LEKMOD policy trees (34.15)

Game logs and the digest identify policies by their internal vanilla-Civ5
IDs (shown in backticks below). LEKMOD keeps those IDs even where it
renames the displayed policy - e.g. `POLICY_MERCHANT_NAVY` is shown
in-game as "Colonialism" - so match on the ID, not the vanilla name it
suggests. Branch openers map to `policy_branch_adopted` events and
finishers to branch completion events.

## Tradition (`POLICY_BRANCH_TRADITION`)
- **Opener:** +3 culture in the capital. +25% faster border growth. Unlocks building the Hanging Gardens.
- **Aristocracy** (`POLICY_ARISTOCRACY`): +15% Production towards Wonders +1 Happiness for every 10 population in a city
- **Legalism** (`POLICY_LEGALISM`): Free Culture Building in your first 4 cities. 2 culture from National Wonders (excluding Palace)
- **Oligarchy** (`POLICY_OLIGARCHY`): Garrisoned Units are maintenance free. +50% City Bombardment Strength in cities with a garrison
- **Landed Elite** (`POLICY_LANDED_ELITE`): +2 food, +15% growth in the capital
- **Monarchy** (`POLICY_MONARCHY`): +1 gold, -1 unhappiness for every 2 population in your capital
- **Finisher:** Free Aqueduct in your first 4 cities. +15% Growth in all cities. Allows purchasing Great Engineers with Faith starting in the Industrial Era.

## Liberty (`POLICY_BRANCH_LIBERTY`)
- **Opener:** +1 culture in each city. Unlocks building the Pyramids.
- **Republic** (`POLICY_REPUBLIC`): +1 Production in each city. +5% Production towards buildings
- **Citizenship** (`POLICY_CITIZENSHIP`): A free Worker appears near the capital. +25% tile improvement rate
- **Collective Rule** (`POLICY_COLLECTIVE_RULE`): A free Settler appears near the capital. +50% Production towards Settlers in the capital.
- **Representation** (`POLICY_REPRESENTATION`): Enters a Golden Age. Each city you found increases the new policy cost by 33% less. +1 Gold from Monuments.
- **Meritocracy** (`POLICY_MERITOCRACY`): +1 happiness and +15% gold from city connections. -5% unhappiness from citizens in unoccupied cities
- **Finisher:** A free Great Person of your choice appears in the capital. +33% production towards all National Wonders.+15% Production towards buildings needed for a National Wonder

## Honor (`POLICY_BRANCH_HONOR`)
- **Opener:** On kill, gain culture equal to the defeated unit’s strength (max. 30). +33% combat strength when fighting barbarians. Unlocks building the Temple of Artemis.
- **Warrior Code** (`POLICY_WARRIOR_CODE`): 2 free Warriors appear near the capital. 4 units are maintenance free. On kill, gain gold (= strength of killed unit, max. 30)
- **Professional Army** (`POLICY_PROFESSIONAL_ARMY`): +50% Production towards Barracks, Armory and Military Academy. They each provide +1 gold, production and culture
- **Military Caste** (`POLICY_MILITARY_CASTE`): Garrisoned units cost no maintenance and give +1 happiness, +2 culture. +2 happiness from courthouse
- **Discipline** (`POLICY_DISCIPLINE`): +100% Production towards Heroic Epic and it provides +4 Food, happiness, culture, production and gold. +50% XP for all non-air units.
- **Military Tradition** (`POLICY_MILITARY_TRADITION`): +50% Production towards Courthouses, which also provide +3 Food, Production, Gold. Citadels provide +1 Food, +2 Science and Culture.
- **Finisher:** +1 Food from Barracks, Armories and Military Academies. On kill, gain science (= strength of killed unit, max. 30). May purchase Great Generals with faith starting in Industrial Era.

## Piety (`POLICY_BRANCH_PIETY`)
- **Opener:** +1 Production, +1 culture, +1 faith in the capital. +50% Production towards Shrines and Temples. Unlocks building the Great Mosque of Djenne.
- **Theocracy** (`POLICY_THEOCRACY`): +33% gold from the Grand Temple. Holy Sites provide +3 gold. +1 gold from each Shrine and Temple
- **Organized Religion** (`POLICY_ORGANIZED_RELIGION`): +1 faith, +1 culture from each Shrine and Temple
- **Mandate of Heaven** (`POLICY_MANDATE_OF_HEAVEN`): +1 faith in the capital. +1 happiness from each Temple. Religious Buildings and Units cost 20% less faith
- **Reformation** (`POLICY_REFORMATION`): Gain a Reformation Belief. +15% Border Growth
- **Religious Tolerance** (`POLICY_FREE_RELIGION`): Cities also gain the pantheon of the second most popular religion. +2 science from each Temple. +25% science from Grand Temple
- **Finisher:** A free Great Prophet appears in the capital. Holy Sites provide +1 food and +3 culture. Receive a Garden in your first 4 cities and allows purchasing 1 great person of every type with exception to a scientist

## Patronage (`POLICY_BRANCH_PATRONAGE`)
- **Opener:** +20 to Influence Resting Point with all City States. Unlocks building the Forbidden Palace.
- **Merchant Confederacy** (`POLICY_MERCHANT_CONFEDERACY`): +2 production, +2 food and +1 Influence per turn from trade routes to City States
- **Scholasticism** (`POLICY_SCHOLASTICISM`): Science per turn for each allied City State and a smaller amount for each friendly City State. Amount based on current Era.
- **Cultural Diplomacy** (`POLICY_CULTURAL_DIPLOMACY`): +100% quantity of resources gifted by City States. +50% happiness from luxuries gifted by City States.
- **Philanthropy** (`POLICY_PHILANTHROPY`): gold gifts to City States are 25% more effective. Influence decays 25% slower.
- **Consulates** (`POLICY_CONSULATES`): +1 World Congress Delegate. +1 additional Delegate each time you enter a new Era, starting with the Industrial Era.
- **Finisher:** Allied City States occasionally gift great people. Friendly and Allied gifts of Culture, Faith and Food are increased by 50%. Military City States gift 2 units.

## Aesthetics (`POLICY_BRANCH_AESTHETICS`)
- **Opener:** Earn Great Writers, Artists and Musicians 25% faster. Unlocks building the Uffizi.
- **Cultural Centers** (`POLICY_CULTURAL_CENTERS`): +100% Production towards Amphitheater, Opera House, Museum and Broadcast Tower. +1 Happiness from Guilds.
- **Cultural Exchange** (`POLICY_CULTURAL_EXCHANGE`): Free Great Writer. +1 culture from Trading post, Brazilwood Camp, Moai, Chateau, Caers, Great Person tiles
- **Artistic Genius** (`POLICY_ARTISTIC_GENIUS`): Free GA, Amphitheater, Opera House, Broadcast Tower, Museum give +1 science, +3 science from Great Works. +2 Science from Festivals.
- **Flourishing of the Arts** (`POLICY_FLOURISHING_OF_THE_ARTS`): +1 culture and tourism from each Great Work and World Wonder. Immediately enter a Golden Age.
- **Fine Arts** (`POLICY_FINE_ARTS`): 3 Culture Specialist Buildings in first 20 cities. Museums, Opera Houses, Broadcast Towers, Amphitheaters: +20% tourism
- **Finisher:** +100% Production towards Archeologists. Double Theming Bonus from Wonders and Museums. Free Social Policy. Shows Hidden Antiquity Sites. Purchase Great Writers, Artist, Musicians with Faith starting from Industrial Era.

## Commerce (`POLICY_BRANCH_COMMERCE`)
- **Opener:** Earn Great Merchants 33% faster. Unlocks building Big Ben.
- **Silk Road** (`POLICY_SILK_ROAD`): +50% Production bonus towards Markets, Banks and Stock Exchanges
- **Mercenary Army** (`POLICY_MERCENARY_ARMY`): May gold purchase Landsknechts at Civil Service and Foreign Legions at Replaceable Parts
- **Mercantilism** (`POLICY_MERCANTILISM`): +2 science from every Market, Bank and Stock Exchange. Purchasing items with gold is 20% cheaper.
- **Entrepreneurship** (`POLICY_ENTREPRENEURSHIP`): +2 trade route slots, 25% less building maintenance, 25% less improvement maintenance
- **Protectionism** (`POLICY_PROTECTIONISM`): +4 production, culture and happiness from East India Company. +1 food, +4 gold from Customs Houses.
- **Finisher:** 2 Free Great Merchants appear. Double gold from Great Merchant trade missions. +1 food from Trading Post and Caers. May purchase Great Merchants with faith starting in the Industrial Era.

## Exploration (`POLICY_BRANCH_EXPLORATION`)
- **Opener:** All Naval units gain +1 movement. Naval combat units gain +1 Sight. Allows the training of Conquistadors. Unlocks building the Tower of Belem.
- **Naval Tradition** (`POLICY_NAVAL_TRADITION`): +1 happiness and culture from each Lighthouse, Harbor and Seaport
- **Maritime Infrastructure** (`POLICY_MARITIME_INFRASTRUCTURE`): +2 prod in every city. +50% prod towards Lighthouses, Harbors and Seaports
- **Colonialism** (`POLICY_MERCHANT_NAVY`): Newly settled Cities start with a free Worker, 6 extra tiles, 2 extra Population, and +2 Local Happiness
- **Navigation School** (`POLICY_NAVIGATION_SCHOOL`): +2 science in every city. All naval units have +10% combat strength
- **Treasure Fleets** (`POLICY_TREASURE_FLEETS`): +1 Food and +1 Production from Coast and Ocean tiles without resources and without improvements .
- **Finisher:** +1 Gold from Coast or Ocean tiles without Resources or Improvements. A free Great Admiral appears. Great Admirals are earned 100% faster. +1 happiness for each unique Luxury resource. May purchase Great Admirals with faith starting from the Industrial Era.

## Rationalism (`POLICY_BRANCH_RATIONALISM`)
- **Opener:** Earn Great Scientists 20% faster. Unlocks building the Porcelain Tower.
- **Sovereignty** (`POLICY_SOVEREIGNTY`): +1 gold from Science buildings
- **Free Thought** (`POLICY_FREE_THOUGHT`): +1 science from Trading Posts and several UI’s, +4 science from Customs Houses and Academies
- **Humanism** (`POLICY_HUMANISM`): +50% Production towards Library, University, Observatory, Public School and Research Lab
- **Scientific Revolution** (`POLICY_SCIENTIFIC_REVOLUTION`): Gain a free Great Scientist
- **Secularism** (`POLICY_SECULARISM`): +2 science from Specialists
- **Finisher:** +10% science while the Empire is happy.
