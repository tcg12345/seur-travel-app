import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {title:"Seur — A trip to remember",description:"Routes, places and memories, shared by the traveler.",robots:{index:false,follow:false},referrer:"no-referrer"};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>;}
