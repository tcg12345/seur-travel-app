'use client';

import Image from 'next/image';
import {useEffect, useRef, useState} from 'react';
import {ArrowDown, ArrowUpRight, Bookmark, Camera, Compass, Globe2, MapPin, Plane, Smartphone, CalendarDays, Users, Sparkles, Check} from 'lucide-react';
import './landing.css';

// Set this to the approved App Store or public TestFlight URL when Seur launches.
const APP_DOWNLOAD_URL: string | null = null;
const chapters = [
  {id:'explore', number:'01', label:'Follow your curiosity', title:<>Find your kind<br/>of <em>somewhere.</em></>, text:'The little café. The incredible hotel. The neighborhood you’ll talk about for years. Explore cities, save what catches your eye, and make a place your own.', tags:['City guides', 'Hotels & dining', 'Saved places'], image:'explore', alt:'Seur city guide showing Rome, a city photograph, saved places and discovery categories', icon:Compass},
  {id:'plan', number:'02', label:'Bring it all together', title:<>A place for<br/><em>every plan.</em></>, text:'Give flights, stays, dinner plans, and days with nothing planned a home. Move between your itinerary, calendar, and map without losing the thread.', tags:['Itineraries', 'Calendars', 'Trip budgets'], image:'plan', alt:'Seur itinerary with a Paris trip, current daily agenda and dinner plan', icon:CalendarDays},
  {id:'world', number:'03', label:'See the bigger picture', title:<>Your world.<br/><em>Beautifully connected.</em></>, text:'See where you’ve been and where you’re going. Explore your places on the globe, follow your flights, and keep the next adventure in sight.', tags:['Interactive globe', 'Flight tracking', 'Trip routes'], image:'globe', alt:'Seur interactive globe showing Europe and Africa, with city discovery and travel navigation', icon:Globe2},
];

function Wordmark({light=false}:{light?:boolean}) {
  return <a href="#top" className={`lp-wordmark ${light?'lp-wordmark-light':''}`} aria-label="Seur home"><Image unoptimized src="/landing/app-icon.png" alt="" width="40" height="40"/><span>seur</span></a>;
}
function GetApp({light=false,small=false}:{light?:boolean;small?:boolean}) {
  return <a href={APP_DOWNLOAD_URL||'#download'} className={`lp-button ${light?'lp-button-light':''} ${small?'lp-button-small':''}`}><span>{APP_DOWNLOAD_URL?'Download Seur':'Get the app'}</span><ArrowUpRight size={18} aria-hidden="true"/></a>;
}
function Phone({image,alt,className='',priority=false}:{image:string;alt:string;className?:string;priority?:boolean}) {
  return <div className={`lp-phone ${className}`}><Image unoptimized src={`/landing/${image}.webp`} alt={alt} width="396" height="860" loading={priority?'eager':'lazy'} fetchPriority={priority?'high':'auto'}/></div>;
}

export default function SeurLanding() {
  const root = useRef<HTMLDivElement>(null);
  const [chapter,setChapter] = useState(0);
  useEffect(()=>{
    const node=root.current;
    if(!node)return;
    const reduced=window.matchMedia('(prefers-reduced-motion: reduce)');
    const updateMotion=()=>{node.dataset.motion=reduced.matches?'reduced':'full';};
    updateMotion();reduced.addEventListener('change',updateMotion);
    // Content is visible by default, including when JavaScript or observers are unavailable.
    const reveals=Array.from(node.querySelectorAll<HTMLElement>('[data-reveal]'));
    const observer=new IntersectionObserver(entries=>entries.forEach(entry=>{if(entry.isIntersecting){entry.target.classList.add('lp-seen');observer.unobserve(entry.target);}}),{threshold:.12});
    reveals.forEach(el=>{if(el.getBoundingClientRect().top>innerHeight){el.classList.add('lp-will-reveal');observer.observe(el);}});
    const steps=Array.from(node.querySelectorAll<HTMLElement>('[data-chapter]'));
    let frame=0;
    const update=()=>{
      frame=0;
      if(!reduced.matches)node.style.setProperty('--lp-scroll',String(Math.min(window.scrollY,1000)));
      const anchor=innerHeight*.5;
      let nearest=0,distance=Infinity;
      steps.forEach((step,i)=>{const r=step.getBoundingClientRect();const d=Math.abs(r.top+r.height/2-anchor);if(d<distance){distance=d;nearest=i;}});
      setChapter(nearest);
    };
    const onScroll=()=>{if(!frame)frame=requestAnimationFrame(update);};
    window.addEventListener('scroll',onScroll,{passive:true});window.addEventListener('resize',onScroll);update();
    return()=>{observer.disconnect();window.removeEventListener('scroll',onScroll);window.removeEventListener('resize',onScroll);reduced.removeEventListener('change',updateMotion);cancelAnimationFrame(frame);};
  },[]);

  return <div className="lp" ref={root} id="top">
    <a className="lp-skip" href="#journey">Skip to app features</a>
    <header className="lp-header">
      <Wordmark/>
      <nav aria-label="Main navigation"><a href="#journey">The experience</a><a href="#memories">Made for the memories</a></nav>
      <GetApp small/>
    </header>
    <main>
      <section className="lp-hero" aria-labelledby="hero-heading">
        <div className="lp-hero-photo"><picture><source media="(max-width: 600px)" srcSet="/landing/coast-mobile.webp"/><Image unoptimized src="/landing/coast.webp" alt="Sunlit Mediterranean-inspired coastline overlooking a calm blue sea" width="1536" height="1024" fetchPriority="high"/></picture></div>
        <div className="lp-hero-shade"/>
        <div className="lp-hero-inner">
          <div className="lp-hero-copy">
            <p className="lp-eyebrow lp-hero-kicker"><span/> A little further from ordinary</p>
            <h1 id="hero-heading">Go somewhere.<br/><em>Feel everything.</em></h1>
            <p className="lp-hero-description">Your places, plans, and favorite moments.<br className="lp-desktop-break"/> Together in one beautiful travel app.</p>
            <div className="lp-hero-actions"><GetApp light/><span>Coming soon for iPhone</span></div>
          </div>
          <div className="lp-hero-product">
            <div className="lp-orbit-note"><Bookmark size={18} aria-hidden="true"/><span>A world worth saving.</span></div>
            <Phone image="globe" alt="Seur’s native iPhone app, with an interactive globe and travel discovery" priority/>
            <div className="lp-hero-caption"><span className="lp-caption-rule"/> Your world, in your pocket.</div>
          </div>
        </div>
        <div className="lp-hero-footer"><span>THE ART OF GOING PLACES</span><a href="#journey">Scroll to explore <ArrowDown size={16} aria-hidden="true"/></a><span>DESIGNED FOR iPHONE</span></div>
      </section>

      <section className="lp-intro lp-wrap" id="journey">
        <p className="lp-eyebrow" data-reveal>From the first idea to the last postcard</p>
        <h2 data-reveal>Less keeping track.<br/><em>More getting lost.</em></h2>
        <div className="lp-intro-bottom" data-reveal><p>Travel is more than getting there.<br/>Seur brings the whole journey together, so you can be a little more present for it.</p><a className="lp-text-link" href="#explore">Meet your travel companion <ArrowDown size={18} aria-hidden="true"/></a></div>
      </section>

      <section className="lp-story lp-wrap" aria-label="Explore the Seur app">
        <div className="lp-story-device" aria-hidden="true">
          <div className={`lp-stage lp-stage-${chapter}`}>
            <span className="lp-stage-word">{['discover','go','wander'][chapter]}</span>
            <div className="lp-stacked-phone">{chapters.map((item,i)=><Phone key={item.id} image={item.image} alt="" className={chapter===i?'lp-phone-active':''}/>)}</div>
            <div className="lp-stage-footer"><span>SEUR / {['EXPLORE','PLAN','YOUR WORLD'][chapter]}</span><span>0{chapter+1} — 03</span></div>
          </div>
          <p className="lp-preview-label">Inside Seur · Example app screens</p>
        </div>
        <div className="lp-chapters">{chapters.map((item,i)=><article key={item.id} id={item.id} data-chapter={i} className="lp-chapter">
          <div className="lp-chapter-copy" data-reveal><p className="lp-eyebrow"><span className="lp-chapter-number">{item.number}</span>{item.label}</p><h2>{item.title}</h2><p className="lp-description">{item.text}</p><ul className="lp-tags">{item.tags.map(tag=><li key={tag}><Check size={14} aria-hidden="true"/>{tag}</li>)}</ul></div>
          <div className="lp-mobile-device"><Phone image={item.image} alt={item.alt}/><p className="lp-preview-label">Inside Seur · Example app screen</p></div>
          <span className="sr-only lp-desktop-description">{item.alt}</span>
        </article>)}</div>
      </section>

      <section className="lp-memories" id="memories">
        <div className="lp-wrap">
          <div className="lp-memories-heading" data-reveal><p className="lp-eyebrow">Some things deserve to stay with you</p><h2>The trip ends.<br/><em>The feeling doesn’t.</em></h2><p>For the places that become part of your story.<br/>And the people who make it worth telling.</p></div>
          <div className="lp-memory-grid">
            <article className="lp-memory-card lp-journal-card" data-reveal>
              <div className="lp-memory-visual lp-journal-visual" aria-hidden="true">
                <div className="lp-photo-print"><Image unoptimized src="/landing/coast.webp" alt="" width="1536" height="1024" loading="lazy"/><span>One of those afternoons.</span></div>
                <div className="lp-journal-note"><Camera size={18}/><span>Keep the moment.</span><Bookmark size={16}/></div>
              </div>
              <div className="lp-memory-copy"><span className="lp-mini-icon"><Camera size={20} aria-hidden="true"/></span><h3>More than a camera roll.</h3><p>Keep photos, notes, and favorite places together in your trip journal. A little time capsule, always with you.</p></div>
            </article>
            <article className="lp-memory-card lp-together-card" data-reveal>
              <div className="lp-memory-visual lp-together-visual" aria-hidden="true">
                <div className="lp-shared-plan"><div className="lp-shared-top"><span>THE NEXT ADVENTURE</span><Users size={20}/></div><h4>A few days away.</h4><div className="lp-shared-row"><Compass size={18}/><span>Somewhere new</span><Check size={17}/></div><div className="lp-shared-row"><CalendarDays size={18}/><span>A plan everyone’s part of</span><Check size={17}/></div><div className="lp-shared-row"><Sparkles size={18}/><span>Room for the unexpected</span><Check size={17}/></div><div className="lp-shared-footer"><div className="lp-initials"><span>A</span><span>J</span><span>You</span></div><span>Better together</span></div></div>
              </div>
              <div className="lp-memory-copy"><span className="lp-mini-icon"><Users size={20} aria-hidden="true"/></span><h3>Good company. One shared plan.</h3><p>Bring your people along. Share trips and saved places, and keep the conversation close to the adventure.</p></div>
            </article>
          </div>
        </div>
      </section>

      <section className="lp-everything lp-wrap" aria-label="More ways to travel with Seur" data-reveal>
        <p>All the little details.<br/><em>Already together.</em></p>
        <ul><li><Plane aria-hidden="true"/>Flight tracking</li><li><MapPin aria-hidden="true"/>Saved places</li><li><CalendarDays aria-hidden="true"/>Trip planning</li><li><Camera aria-hidden="true"/>Travel journals</li></ul>
      </section>

      <section className="lp-download" id="download" aria-labelledby="download-heading">
        <div className="lp-download-background" aria-hidden="true"><Image unoptimized src="/landing/coast.webp" alt="" width="1536" height="1024" loading="lazy"/></div>
        <div className="lp-download-content" data-reveal><Image unoptimized className="lp-app-icon" src="/landing/app-icon.png" alt="Seur app icon" width="86" height="86"/><p className="lp-eyebrow">Take a little wonder with you</p><h2 id="download-heading">Your next chapter.<br/><em>In your pocket.</em></h2><p>A more thoughtful way to travel.<br/>Made for wherever life takes you.</p>{APP_DOWNLOAD_URL?<a className="lp-button lp-button-light" href={APP_DOWNLOAD_URL}><Smartphone size={20}/>Download Seur<ArrowUpRight size={18}/></a>:<div className="lp-availability"><Smartphone size={24} aria-hidden="true"/><div><strong>Coming soon for iPhone</strong><span>The journey is just beginning.</span></div></div>}<span className="lp-download-note">{APP_DOWNLOAD_URL?'Discover Seur on your iPhone.':'The download link will be here when Seur launches.'}</span></div>
      </section>
    </main>
    <footer className="lp-footer lp-wrap"><div className="lp-footer-top"><Wordmark/><span>Go well. Come back with stories.</span><a href="#top" className="lp-back-top">Back to top <ArrowUpRight size={17} aria-hidden="true"/></a></div><div className="lp-footer-bottom"><span>© {new Date().getFullYear()} Seur</span><span>Thoughtfully made for iPhone.</span><span className="lp-photo-note">Coastal artwork created for Seur.</span></div></footer>
  </div>;
}
