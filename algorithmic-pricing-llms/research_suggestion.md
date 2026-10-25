### Weekend project

Reduce the default sweep (the repository's grid of prompt prefixes and demand parameters) to one prompt, parameter value and seed, and first verify sustained prices above the competitive benchmark. Then vary only one feature, for example 0, 10 or 100 visible rounds (the length of price history included in each prompt, not the game length); persistent notes on/off (the plans-and-insights scratchpad from Fish et al.); stable versus shuffled seller names; or temperature, while holding the economics fixed.


### Resources

Low-to-medium setup risk. A 300-round two-agent run makes about 600 sequential model calls. Twelve to 24 pilot runs require roughly 7,200 to 14,400 calls. Use one low-cost API provider, a 16 GB laptop and no GPU; budget about $20 to $100.