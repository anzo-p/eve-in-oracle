# A small Data Engineering exercise

This project experiments with data engineering and it actually made me rich in a video game through providing guidane for more optimal business decisions. It demonstrates that there is no limit for as to how high you may refine your information ([link](https://github.com/anzo-p/eve-in-oracle/blob/b4f763331b5972e0729519fbf1f61944ca6f4b55/4_reports/materials.sql#L236)) even out of very simple data *but only if you keep your Schema intact, through all the layers*.

---

The system began with a question: What should we manufacture right now, in the everchanging market situation, in order to make the most profit?

```
show us what produces to build out of items in order to make huge profit
include information on what items are required to build those
also show us itemwise breakdown on those items like item price, required quantities, total price
help us understand which items comprise most to the final expenses - ie. which ones to look for bargains

    FROM rules that tell how items can be combined together into produces - items of higher value
    FROM item data
    FROM market data on those items - buy sell prices, quantities, and locations

WHERE the produces has actual demand in the market
AND   the supply demand price discrepancy, buy/sell -spread is high
AND   for goodness sake, show us all the data in a single result, dont make us run many queries
```

If you want data to tell you smart things and give you guidance in business decisions, you **must** start with smart questions and then let data tell you the answers. (Most often in a reciprocal way, where you gain some answers that guides you to shape further quesitons from the data and so on.)

It won't work without smart questions

And certainly not by attempting to figure those smart answers outside the data, introspectively by yourself, and then just fetch the supposedly right results from that data.

---

The refining of information happens through layers on top of previous refine - queries on top of subqueries

```
SELECT ...
FROM  (SELECT ...) top
WHERE  field IN (SELECT ...
                 FROM  (SELECT ...) nxt
                 WHERE  field IN (SELECT ...
                                  FROM  (SELECT ...)) trd
                                  WHERE  field IN ( ..no theoretical limit.. ) ))
```

You may even JOIN those subqueries any way you please for as long as there are meaningful fields for the JOIN, ie. you kept the Schema intact through the layers

```
SELECT ...
FROM   (SELECT ...) top
WHERE  field IN (SELECT ...
                 FROM       (SELECT ...) nxt
                 INNER JOIN (SELECT ...) trd ON nxt.fields = trd.fields
                 WHERE  ...
```

Technically this mans that, should you use a relational database model and SQL, which are specifically invented to do so, then you **must** follow the following rules:
- referential integrity - your related data, the FOREIGN KEYs in one table, to the row identificaiton in that related table, must link together unambiguously
- field normalization - your one collection of data, the table, must only conain fields that are functionally depended on each others - for the given situation, and so
  - your *core fact* tables **must** be normalized
  - *special purpose VIEWs* to produce some desired/proper structuring, typically aggregation, for the next layer, may be denormalized, but they will only remain useful for that next layer in that given stack of queries
- data integrity - your schema must resist values that are meaningless or ambiguous to any fields, through CONSTRAINTs that you need to define

Failure to follow these rules will result in..

---

## Garbage

Should you, however, let ambigous data of non-integrity into the system, then starting from that data you will only get garbage but no longer any information of higher refine. Below is a table to illustrate this. On the left side there remains no limit for as to how high you may refine your data. On the right side the acquisition of more clever information stops at the layer that is let to succumb to garbage.

| We keep pulling out smarter and smarter information | We are just getting garbage |
| ------------- | ----------- |
| SELECT FROM layer below some real clever info that is only possible because intact smart layers below | SELECT on top of that will give us garbage |
| SELECT FROM layer below with another set of value add rules | we let a little bit of garbage in because [reasons] |
| SELECT FROM layer below with some value add rules | SELECT FROM third.. |
| SELECT FROM elementary data with some value add rules | SELECT FROM second.. |
| SELECT FROM elementary data | SELECT FROM first.. |

---

## Performance

Eventually, when adding more an more queries on top, the system will choke because there just are too many layers, subqueries to compute in a single query. For performance, you need to *materialize* ([link](https://github.com/anzo-p/eve-in-oracle/blob/b4f763331b5972e0729519fbf1f61944ca6f4b55/1_create/7_create_view.sql)) some of those layers, result sets of previous queries - have them precomputed so that the system can compute all those layers fast enough. Materializations of precomputed results is, in a nutshell, how all real-timelike performance is achieved in computing. This is true from small algorithms ([link](https://gist.github.com/anzo-p/4d7ddc5529a05dcf9e09aa3ee746dfc7)) all the way to distributed systems of hundreds of millions of users.

---

Relational Database Systems (RDBMS or RDS) were cool things back in the day, and even today, because of their potential, remain a fascinating curiosity to say the least.

Centralized RDBMS's just arent putting out data quickly enough to meet the requirements for performance and volumes of data of modern applications that have a distributed deployment architecture, because of so many users.
