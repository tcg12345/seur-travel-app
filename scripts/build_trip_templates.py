"""Build the hand-edited starter itineraries from Seur's local catalog. No provider calls."""
import json, uuid, datetime
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CAT = {h['id']: h for h in json.loads((ROOT/'iOS/Aurum/Resources/hotels.json').read_text())}
def uid(s): return str(uuid.uuid5(uuid.NAMESPACE_URL, 'https://seur.app/templates/'+s))
def day(n): return (datetime.date(2000,1,1)+datetime.timedelta(days=n)).isoformat()
def place(name, city, category='attraction', **extra):
    return dict(id=uid(city+name), name=name, category=category, city=city, address='', phone='', website='', source='Seur editorial', overview='', **extra)
# Titles, taglines, seasons and daily pacing are editorial choices, not generated recommendations.
BLUEPRINTS = [
 ('riviera','The Riviera, slowly','Six nights of grand hotels, sea air and unhurried dinners from Monaco to St-Tropez.',['luxury','beach','food'],'Late spring to early autumn',[
  ('Monte Carlo',2,'Europe/Monaco',43.7384,7.4246,'riviera-paris', [['Arrive and settle in','Casino Square stroll','Le Louis XV'],['Monaco old town','An open afternoon by the sea','Le Grill']]),
  ("Cap d’Antibes",2,'Europe/Paris',43.5528,7.1297,'riviera-eden', [['Transfer to Cap d’Antibes','Settle in by the water','Louroc'],['Antibes old town','Leave the afternoon for the coast',"Giovanni’s"]]),
  ('St-Tropez',2,'Europe/Paris',43.2677,6.6407,'riviera-cheval',[['Transfer to St-Tropez','Harbour and old-town walk',"La Vague d’Or"],['A slow beach morning','Free time in St-Tropez','La Terrasse']])]),
 ('copenhagen','Copenhagen, by design','Three nights of waterside walks, Danish design and a memorable table.',['design','food','city'],'May to September',[
  ('Copenhagen',3,'Europe/Copenhagen',55.6761,12.5683,'copenhagen-angleterre',[['Arrive and settle in','Nyhavn and the waterfront','Marchal'],['Designmuseum Danmark','A relaxed afternoon around Frederiksstaden','Choose a neighbourhood dinner'],['Rosenborg and the King’s Garden','Time for shops and coffee','An unhurried final dinner']])]),
 ('paris','Paris beyond the rush','Four nights with one anchor each morning and enough space to enjoy the city between meals.',['luxury','art','food'],'Spring or autumn',[
  ('Paris',4,'Europe/Paris',48.8566,2.3522,'par-ritz-paris',[['Arrive and settle in','Place Vendôme and the Tuileries','Bar Vendôme'],['A morning at the Louvre','A long café break','Choose a Left Bank dinner'],['Musée d’Orsay','Walk along the Seine','Salon Proust'],['Explore the Marais','An afternoon for your own discoveries','Bar Vendôme']])]),
 ('london','London, at an easy pace','Mayfair as your base, great museums and a final evening left for a show.',['luxury','art','city'],'Spring or autumn',[
  ('London',4,'Europe/London',51.5074,-0.1278,'lon-claridges',[['Arrive and settle in','A Mayfair walk',"Claridge’s Restaurant"],['The British Museum','Coffee and bookshops in Bloomsbury','Choose a Soho dinner'],['The Victoria and Albert Museum','Hyde Park at your own pace',"Claridge’s ArtSpace Café"],['Browse Marylebone','An open afternoon','Choose a West End performance']])]),
 ('singapore','Singapore after the rain','Heritage streets, shaded pauses and three nights built around food.',['food','culture','city'],'Year round; allow for tropical showers',[
  ('Singapore',3,'Asia/Singapore',1.3521,103.8198,'sg-raffles',[['Arrive and settle in','Civic District walk','Tiffin Room'],['Gardens by the Bay','A cool indoor afternoon','Choose a hawker-centre dinner'],['Explore Chinatown','Coffee and independent shops','The Grand Lobby']])]),
 ('dubai','Dubai with breathing room','Three nights balancing the waterfront, old Dubai and quiet time at your hotel.',['luxury','beach','culture'],'November to March',[
  ('Dubai',3,'Asia/Dubai',25.2048,55.2708,'dxb-burj-al-arab',[['Arrive and settle in','A relaxed waterfront afternoon','Al Iwan'],['Al Fahidi and Dubai Creek','Return for a quiet afternoon','Choose an evening by the water'],['A slow beach morning','Time to explore at your own pace','Al Iwan']])]),
 ('tokyo','Tokyo, one neighbourhood at a time','Four nights of gardens, galleries and deliberately unhurried neighbourhood days.',['design','food','culture'],'Spring or autumn',[
  ('Tokyo',4,'Asia/Tokyo',35.6762,139.6503,'tyo-aman-tokyo',[['Arrive and settle in','Marunouchi at a gentle pace','Arva'],['Asakusa and Sensō-ji','Coffee and shops in Kuramae','Choose an Asakusa dinner'],['Meiji Jingū','An open afternoon in Aoyama','Arva'],['A museum morning in Ueno','Leave time for your favourite neighbourhood','Choose a final neighbourhood dinner']])]),
 ('hong-kong','Hong Kong, harbour to hillside','Three nights linking the waterfront, a hillside walk and time around the table.',['food','city','luxury'],'October to December',[
  ('Hong Kong',3,'Asia/Hong_Kong',22.3193,114.1694,'hkg-peninsula',[['Arrive and settle in','Tsim Sha Tsui waterfront','Felix'],['Central and Sheung Wan','An afternoon for galleries and tea','Chesa'],['Victoria Peak, weather permitting','Free time by the harbour','The Lobby']])]),
 ('bangkok','Bangkok from the river','Three nights with early cultural visits, cool afternoon pauses and dinners along the river.',['food','culture','luxury'],'November to February',[
  ('Bangkok',3,'Asia/Bangkok',13.7563,100.5018,'bkk-mandarin-oriental',[['Arrive and settle in','A gentle riverside afternoon','Choose a riverside dinner'],['Wat Pho','A cool afternoon at your hotel',"The Authors’ Lounge"],['Explore historic riverside streets','Time for a market or a quiet pause','Anne-Sophie Pic at Le Normandie']])]),
 ('new-york','New York, a little less hurried','Four nights of park walks, museum mornings and room for a neighbourhood detour.',['art','food','city'],'Spring or autumn',[
  ('New York',4,'America/New_York',40.7128,-74.0060,'nyc-the-plaza',[['Arrive and settle in','Central Park at your own pace','The Palm Court'],['The Metropolitan Museum of Art','An Upper East Side afternoon','Choose a neighbourhood dinner'],['Walk the West Village','An afternoon for shops and coffee','Choose a downtown dinner'],['A museum or gallery of your choice','Free time before the evening','Choose a Broadway performance']])])]
EXTRA = {
'riviera-paris': dict(name='Hôtel de Paris Monte-Carlo', address='Place du Casino, Monte Carlo, Monaco', website='https://www.montecarlosbm.com/en/hotel-monaco/hotel-de-paris-monte-carlo', country='Monaco'),
'riviera-eden': dict(name='Hôtel du Cap-Eden-Roc',address='Boulevard J. F. Kennedy, Antibes, France', website='https://www.oetkerhotels.com/hotels/hotel-du-cap-eden-roc/',country='France'),
'riviera-cheval': dict(name='Cheval Blanc St-Tropez',address='Plage de la Bouillabaisse, Saint-Tropez, France',website='https://www.chevalblanc.com/en/maison/st-tropez/',country='France'),
'copenhagen-angleterre': dict(name='Hotel d’Angleterre',address='Kongens Nytorv 34, Copenhagen, Denmark',website='https://www.dangleterre.com/',country='Denmark')}
DINNERS = {
 'riviera': ['Le Louis XV', 'Le Grill', 'Louroc', 'Giovanni’s', 'La Vague d’Or', 'La Terrasse'],
 'copenhagen': ['Marchal', 'Aamanns 1921', 'Høst'],
 'paris': ['Bar Vendôme', "L'Espadon", 'Bar Vendôme', "L'Espadon"],
 'london': ['Dante Mayfair', "L'Epicerie", 'Dante Mayfair', "L'Epicerie"],
 'singapore': ['Tiffin Room', 'Yi by Jereme Leung', "Butcher's Block"],
 'dubai': ['Al Iwan', 'Al Mahara', 'Al Muntaha'],
 'tokyo': ['Arva', 'Musashi by Aman', 'Arva', 'Musashi by Aman'],
 'hong-kong': ['Felix', 'Chesa', "Gaddi's"],
 'bangkok': ['Sala Rim Naam', 'Baan Phraya', 'Anne-Sophie Pic at Le Normandie'],
 'new-york': ['The Mark Restaurant by Jean-Georges', 'Casa Tua', 'Caviar Kaspia at The Mark', 'The Mark Restaurant by Jean-Georges'],
}
DINING_LINKS = {
 'Aamanns 1921': ('Niels Hemmingsens Gade 19-21, Copenhagen', 'https://aamanns.dk/restaurant/aamanns-1921/'),
 'Høst': ('Copenhagen, Denmark', 'https://cofoco.dk/en/restaurant/hoest'),
}
result=[]
for slug,title,tagline,tags,season,stages in BLUEPRINTS:
    doc=dict(id=uid(slug),kind='journey',title=title,destination=' → '.join(s[0] for s in stages),description='',dateMode='nights',visibility='public',isTemplate=True,templateMeta=dict(tagline=tagline,tags=tags,suggestedSeason=season,authorHandle='seur_editors',cloneCount=0,includesCosts=False,includesRatings=False),stops=[],events=[],hotels=[],flights=[],places=[],updatedAt=1788825600)
    offset=0
    for city,nights,zone,lat,lon,hid,days in stages:
        h=EXTRA.get(hid) or CAT[hid]
        stop=dict(id=uid(slug+city),name=city,code='',country=h['country'],arrival=day(offset),nights=nights,latitude=lat,longitude=lon,timeZone=zone)
        doc['stops'].append(stop)
        hotelplace=place(h['name'],city,'hotel');hotelplace.update(address=h.get('address',''),website=h.get('website',''))
        doc['hotels'].append(dict(id=uid(slug+hid),place=hotelplace,checkIn=day(offset),checkOut=day(offset+nights),guests=2,rooms=1,roomType='',confirmation='',notes='',overview=''))
        venue_names=[v['name'] for v in h.get('venues',[])]
        for local,activities in enumerate(days):
            activities = activities[:2] + [DINNERS[slug][offset+local]]
            for index,name in enumerate(activities):
                minute=[600 if local else 900, 900 if local else 1020, 1200][index]
                is_dining=index==2 and not name.startswith('Choose') and 'dinner' not in name.lower()
                p=place(name,city,'restaurant' if is_dining else 'attraction')
                if is_dining:
                    venue_hotel=next((v for v in CAT.values() if v['city']==city and any(z['name']==name for z in v['venues'])), None)
                    if name in DINING_LINKS: p.update(address=DINING_LINKS[name][0],website=DINING_LINKS[name][1])
                    elif venue_hotel: p.update(address=venue_hotel.get('address',''),website=venue_hotel.get('website',''))
                    elif hid in EXTRA: p.update(address=h.get('address',''),website=h.get('website',''))
                event=dict(id=uid(slug+city+str(local)+str(index)),seriesID=uid(slug+city+str(local)+str(index)+'series'),stopID=stop['id'],day=local,minute=minute,place=p,description='',links=[],durationMinutes=90 if index==2 else 120)
                if name.startswith(('Choose','A slow','Free time','Leave','Time for','An open','An unhurried','A cool','Return','A relaxed','Arrive','Transfer')):
                    event.update(kind='transfer' if name.startswith('Transfer') else 'freeTime',title=name)
                doc['events'].append(event)
        offset+=nights
    result.append(doc)
(ROOT/'iOS/Aurum/Resources/TripTemplates.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print('Built',len(result),'editorial templates')
