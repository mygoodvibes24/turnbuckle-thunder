# Story Mode: "Kitchen Champion"

City 2 City Wrestling: Backyard Brawl. Data lives in `scripts/story_data.gd` (`CAST`, `CHAPTERS`).

Tank Magruder is 26 (he says "twenty-five and a half, emotionally"). He has no job, he lives with his mom, and he has a dent-shaped hole in her refrigerator. His half of the rent is $600, it's due on the first, and backyard wrestling just paid him eleven dollars in tips. Over eight chapters he goes from the yard to a rooftop contract, loses everything to the fine print, and wins it back at the block party in front of the whole neighborhood. His mom is there for her first Saturday off in three years.

## The arc

| Act | Chapters | What happens |
|---|---|---|
| Rise | 1-4 | Rent money, one yard at a time. The channel grows, a pop star and a hype MC notice him, and he pays the rent himself. |
| The trap | 5 | Preston Vale signs him on a rooftop. Eleven pages, tiny font. |
| Setback | 6 | Page nine: Vale owns the channel, Tank's likeness and his catchphrases, and he orders Tank to lose on purpose. Pickles quits. Tank and Mom have the big kitchen fight. Tank wins honestly anyway, and Vale cuts him loose but keeps the channel. |
| Comeback | 7 | Tank sits on the roof at 2 AM, and Mom turns out to be the channel's #1 fan. The grumpy neighbor turns out to be a retired champion. Pickles comes back, and they start a new channel from scratch. |
| Finale | 8 | Block party main event against Vale's star, Yung Halo, with both men's freedom riding on it. Every rival turns up as an ally. |

## Cast

**Roster fighters** (look comes from `roster.gd`)
- **TANK MAGRUDER**: big heart, bigger fridge dent. He can't read a contract, but he won't throw a fight.
- **LIL PELIGRO**: the kid next door with a trampoline. He's the first opponent, and by Chapter 7 he's the undefeated "People's Champ" whose only loss was to Tank.
- **RAZZ DECIBEL**: punk frontman of the Gutter Choir. He wants the yard for a show, then ends up playing Tank's entrance music forever ("We learned a SECOND CHORD").
- **STARLA VOLT**: pop star who hires Tank as the villain in her "Heartbreak Suplex" video, then calls him her co-star.
- **DUSTY BUCKLES**: quiet cowboy sending every dollar home for Grandma's well pump. Tank gives him $100 of his winnings, and Dusty pays it back in pie at the finale.
- **BOOM BAP BOOKER**: old-school legend. He knows the fight is rigged and refuses a gift: "Bring everything, or don't bring nothing."
- **YUNG HALO**: Vale's star, smug at first but trapped by the same contract. He's the finale opponent, and becomes an ally once he's free.

**NPCs** (they have their own `look` dicts)
- **MOM: Bernadette Magruder.** CNA in a county ER who works doubles, in teal scrubs and white clogs. She's warm and sharp and the emotional core of the story. She calls him "Theodore" when he's in trouble. Her hidden pride is the reveal: she is **Scrubs_N_Slams**, the channel's #1 commenter ("PROTECT YOUR NECK BABY"). The whole nurses' station watches.
- **PICKLES (Darnell Pickett)**: best friend and cameraman. He films on the Broomcam (a phone duct-taped to a broom), later upgraded to the Mopcam. His catchphrase is "THAT'S THUMBNAIL."
- **MR. HOLLIS**: the grumpy neighbor with prize hydrangeas. Secretly **Hurricane Hollis**, six-time regional champion, who becomes Tank's trainer.
- **RUDY TWO-TIMES**: scrappy promoter who runs fights behind the store lot and says everything twice.
- **PRESTON VALE**: slick influencer-promoter who runs Vale Elite. He's the one true antagonist ("Welcome to the family").
- **MC LAWN DART**: the in-game hype MC, in person. He runs the hype channel LAWN DART LIVE.

## Running jokes and callbacks
- **The good cheese** is off limits, and the chili is always in the blue dish. On the roof in Ch7, Mom brings the good cheese herself.
- **Gerald**, Mrs. Okafor's nephew, wants Tank's room. "Gerald has a JOB. Gerald has a FERN." He's still asking about the room in the last line of the story.
- **Eleven dollars**, the first tips ever. It comes back in the finale: "For everybody who paid eleven bucks to believe."
- **Scrubs_N_Slams** comments on every video until the Ch7 reveal.
- **The hydrangeas** suffer in every yard match. The finale venue is Hydrangea Street.
- **"More noise than you'll ever make"**, Hollis in Ch2, which pays off in Ch7.
- **Page nine.** Pickles warns Tank about it and Halo begs him to read it. Mom: "Page nine is now confetti."
- **"SOMEBODY CALL HIS MAMA!"** is MC Lawn Dart's in-game line. In the finale: "...Oh. She's right here. And she is NOT playing!"
- **The Kitchen Championship** is a cereal-box-and-tinfoil belt nine-year-old Theodore made. Mom kept it, and it's the only title that counts in her house.

## Chapters

| # | Title | Opponent | CPU | Payout | Bonus |
|---|---|---|---|---|---|
| 1 | Rent Is Due | Lil Peligro | 0.30 | $100 | Fridge Drop x1 (+$25) |
| 2 | Noise Complaint | Razz Decibel | 0.37 | $150 | Break a table (+$40) |
| 3 | Heartbreak Suplex | Starla Volt | 0.44 | $250 | 2 air tricks (+$50) |
| 4 | Two-Times Tuesday | Dusty Buckles | 0.50 | $400 | Perch dive (+$60) |
| 5 | Sign Here | Yung Halo | 0.57 | $600 | 4,000 style (+$80) |
| 6 | Page Nine | Boom Bap Booker | 0.64 | $750 | Fridge Drop x2 (+$75) |
| 7 | Back to the Yard | Lil Peligro (rematch) | 0.72 | $1,000 | 4 air tricks (+$100) |
| 8 | Block Party | Yung Halo (finale) | 0.80 | $2,500 | 6,000 style (+$250) |

1. **Rent Is Due** (kitchen / bedroom / backyard). Mom gives the $600 ultimatum over the fridge dent. Pickles brings the first $11 in tips and introduces the Broomcam. Peligro challenges Tank for the yard while Mr. Hollis guards his hydrangeas. *Win:* $100, and Scrubs_N_Slams says "ice that shoulder." *Lose:* "Ma's gonna rent my room to a fern."
2. **Noise Complaint** (porch / street / backyard). Mom, sixteen hours into her shift, isn't impressed by $100. Razz claims the yard for his band, because "over my dead body" is a yes in punk. Hollis hints at a past. *Win:* Mom texts "why is my folding table on the internet in four pieces," and Tank realizes she watches.
3. **Heartbreak Suplex** (bedroom / store lot). LAWN DART LIVE reposts the Razz match and Starla DMs. Tank is cast as the villain ("you look like a guy who'd eat a girl's fries"). Lawn Dart shows up in person. *Win:* Starla promotes him to co-star.
4. **Two-Times Tuesday** (kitchen / store lot). Over the stolen cheese, Mom admits why she worries: "My knees hurt for strangers every night. One of us is enough." Rudy books Tank against Dusty, who's fighting for Grandma's well pump. *Win:* Tank gives Dusty $100 of the purse.
5. **Sign Here** (kitchen / rooftop). Tank pays the rent and Mom counts it twice "because I want to count it again." On a rooftop, Vale's contract gets signed despite Pickles' warning and Halo's quiet "you should read it." *Win:* Vale pays in full and says "Welcome to the family."
6. **Page Nine** (bedroom / kitchen / street). The channel is now TANK THE GOON, Vale orders a dive, and Pickles walks. Then comes the kitchen fight: "I never asked you for easier. I asked you to show up." Booker refuses a rigged win. *Win:* "Keep it. I'm keeping me." The crowd's hat pays $750.
7. **Back to the Yard** (rooftop / backyard / street). It's 2 AM on the roof, and Mom reveals she's Scrubs_N_Slams: "I was never ashamed of the wrestling, baby. I was scared of it." Hollis becomes Hurricane Hollis and Tank's trainer. Pickles returns with the Mopcam and a new channel. To get the block party main event, Tank has to beat Peligro, now the People's Champ. *Win:* 12,000 subscribers in a night, and "nobody owns it but us."
8. **Block Party** (kitchen / car / street / backyard). Mom gives him the Kitchen Championship and reveals Vale bet Tank's contract on the match. In the car, Halo confesses he's trapped too: "If you win, maybe nobody has to be." All four rivals show up as allies, and Mom stares down Vale. *Win:* Mom announces page nine is confetti, Pickles counts $2,500 and 200k views, and she gives him the Kitchen Champion of the World title. "Rent's still due on the first." THE END... for now. *Lose:* "I did not take a Saturday off to watch you nap in the grass. UP."

## Notes for the engine and flow work
- Every match uses `location: "backyard"`, since that's the only arena. The scripts put each fight in a yard: Starla's aunt's yard, Rudy's cousin's yard, and the block party yard.
- `who` is always a CAST id that's in that scene's `cast`, or `narrator` / `phone` / `tv`. All lines are 140 characters or fewer and plain ASCII.
- Each chapter's `win` scene shows a `cash` pop equal to its `payout`. Ch1's intro also pops +$11.
