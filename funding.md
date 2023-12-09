
## Funding Module 

### Overview 

Coordination-play offers funding tools for an organization to raise funds from investors. It enables coordination between investors and projects enforced by onchain contracts. 

### Motivation 

Many crypto native DAOs and projects that need to raise funds to fund their development are forced into inflexible standard VC contracts that do not fit well with the programmable onchain world. 

We envision a richer set of programmable equyity primitives that allow onchain projects to sell ownership of the project while providing guarantees to investors. The first guarantee we have implemented is: 
1. Spending conditions: Conditional spending of funds raised (tap streaming over x period, milestones, investor approval..etc)
2. Withdrawability guarantees: Ability to redeem locked investment (burn tokens) if some x conditions are not met 

We envision a lot more guarantees that investors would like that can be composably added to the protocol. 


### The round: a Venture stage funding 

It is a venture stage funding contract called `Round`. 

A round is a finite funding requirement by the existing team and defines the following:
1. Funding targets: Exact funding target, tokens on offer 
2. Pricing Function: rising price curve (first come first serve) 
3. Governance rights: Voting rights on some issues
4. Liquidity unlock conditions 
5. Spending conditions 

note: A round in traditional startups is usually thought of as one of pre-seed, seed, series-A, series-B,..etc.

### use 


