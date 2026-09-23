---
layout: post
title: "How to Eat Like Me"
date: 2026-09-23 01:13:00
---
Just under a year ago I processed my entire accessible financial history into
plaintext format for use with the [Ledger](https://ledger-cli.org/) tool.
Comprising this was 7 years of banking transactions (there are no records older
than this made available to me by my bank) and 5 years of credit card
statements. It was an extremely onerous effort, so much so that I wrote my own
software tool, [Reconcile](https://github.com/eacrawford02/reconcile), to aide
in the categorization of all these transactions and the generation of the
plaintext ledger files. My goal here was to consolidate all my financial records
into a single, human-readable store of data that would be portable between OS
environments and could easily be version-controlled. Furthermore, the hope was
that the plaintext format and integration with Ledger would make analysis of the
data with custom scripts and third-party tools possible. Prior to this I'd been
flying by the seat of my pants, budgeting off of last month's cashflow and
having long ceased the tracking of my expenditures. This worked fine when I was
in school, with summer income and RESP disbursements more than covering tuition,
rent, and whatever other meager expenses I had. But the real-adult world is more
complex: rent has more than tripled since my student days, car ownership is
increasingly pricey, it's gotten harder to have fun on the cheap, and so on and
so forth. I will admit that a good deal of this is self-inflicted (I like nice
things); however, that's beside the point, which is that there's but a slim
margin between what comes in and what goes out every month--hence the need for
all this tracking and budgeting. Big surprise, I know. Visibility into my
month-to-month income has also become more opaque as a consequence of equity and
bonus compensation structures (I'll occasionally go from being taxed through the
nose one month to getting a whackload of shares delivered to my brokerage
account the next), which complicates any sort of basic cashflow analysis.

So what does all of this have to do with eating? Well, there was one burning
analytical question I had about my finances: what is the average amount of money
I spend on a typical, home-cooked meal? I find eating well to be an exhausting
endeavor. The planning, the grocery shopping, the cooking, the cleaning, the
actual act of sitting down and eating--it's like the ultimate Sisyphean task.
Hours of my week, every week, dedicated to this one ritual. But what if it
didn't have to be this way? What if I could eat something ready-made for less
than what it would cost me (in both money and time) to cook something equally as
nutritious? There are plenty of prepared and semi-prepared meal services out
there: Factor, Goodfood, HelloFresh, etc. How much of a premium do they actually
command?

On the surface, it seems like an easy question to answer: pick range (e.g., a
month in recent history), and have Ledger report the running total of
expenditures categorized as groceries over that range, then divide by the
product of the number of days in that range and the number of meals made per
day. The following Ledger command would do just that:

```
ledger -f ledger.dat --begin 2025-01-01 --end 2026-01-01 register Expenses:Groceries
```

The problem with this simplistic approach is that my yearly/monthly/weekly
grocery bill is misrepresentative of what my actual grocery spend **ought** to
be. For example, I get lunch catered by my current employer every Friday,
artificially reducing my grocery bill by the cost of one meal per week. The same
would apply to a weekend spent visiting my parents. I would even consider
ordering takeout as uncharacteristic of a "home-cooked meal" due to how much
more expensive it typically is. While I could in theory exclude those from my
calculation by reducing the number of days (in `1 / # of meals per day`
increments) over which I divide the running total by, this would be tedious,
especially over the range of days required to give a good average. But what if
there was a time when I never skipped a trip to the grocery store? A time when I
was, at least in my head, too broke to eat out? A time when I truly had to fend
for myself? Yes... my undergrad years, sweet days of abandon.

Of course I can't just take that contiguous four-year span in its entirety.
Summer breaks were spent at home, so May through August are out. And between
reading weeks in October and February, Christmas break spanning parts of
December and January, that leaves only September, November, and March (I've
elected to omit April since we'd usually be out of school a week or two before
the end of the month). First year's out due to living in residence, and I didn't
start hitting the gym in earnest (and eating accordingly) until May of 2022, so
I won't consider second year either. That ultimately leaves me with 6 months to
work with, which is probably enough for a fairly representative average.

So what I'd need to do would be to calculate a running total of grocery
expenditures over that entire disjoint range, count the number of days spanned,
then use those two figures (along with a four meal per day figure) to calculate
the average.

> **/?\\**{:#mono} Why four meals per day? At my peak (generally at least 7.5 K
> steps per day in combination with at most 8 hr in the gym per week) I was
> consuming roughly 3200 kcal per day for a moderate level of weight gain, with
> 3000 kcal per day being enough to maintain my weight. At four meals per day,
> that's between 750 and 800 kcal per meal, which I feel is a reasonable amount,
> although probably still a bit on the high side.
{:.aside}

Furthermore, because we're talking about spending data from several years ago,
it would only be right to aggregate transactions into months and adjust each for
inflation. Neither of these two things are features offered by Ledger, so I'd
need to roll my own implementation, using Ledger only as a nifty querying tool.
A workaround to get Ledger to return inflation-adjusted amounts is to use a
price history file, wherein the past value of a present-day dollar is specified
for each month of interest. Consider the following price history file:

```
D CPI1,000.00

P 2022-09-01 CPI $0.90
P 2022-11-01 CPI $0.91
P 2023-03-01 CPI $0.92
P 2023-09-01 CPI $0.94
P 2023-11-01 CPI $0.94
P 2024-03-01 CPI $0.95
P 2026-06-01 CPI $1.00
```

In it, the dynamic exchange rate between present-day dollars and an arbitrarily
named commodity representing one dollar at some point in the past (effectively a
list of discount factors) is recorded. If we were to then instruct Ledger to
convert all amounts to the `CPI` commodity via the `--exchange` option, it would
divide each nominal dollar found in the input file by the exchange rate at that
point in time to give the corresponding dollar amount today in real terms.  To
generate this kind of price history file, I wrote an [R script]({{
"/raw-viewer/?file=/assets/code/fetch_cpi.R" | remove_first: '/' | absolute_url
}}){:target="_blank"} to, given a list of month ranges, pull monthly CPI figures
from the amazing [Statistics Canada
API](https://www.statcan.gc.ca/en/developers/wds/user-guide) (specifically the
["Consumer Price Index, monthly, not seasonally adjusted"
table](https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1810000401)), then
walk backward from the current month to calculate the month-on-month percentage
CPI changes and, subsequently, the discount factors.

With the means to generate a price history file secured, I wrote a [Bash
script]({{ "/raw-viewer/?file=/assets/code/price_per_meal.sh" | remove_first:
'/' | absolute_url }}){:target="_blank"} to parse a user-supplied list of month
ranges, feed that to the R script, then sum up the real amounts of all
transactions under my groceries account that fall within those ranges and
calculate the averages.

> **/?\\**{:#mono} The linked Bash script depends on a function from this other
> [helper script]({{ "/raw-viewer/?file=/assets/code/gen_transaction_helper.sh"
> | remove_first: '/' | absolute_url }}){:target="_blank"}.
{:.aside}

Now, for the moment of truth:

```
$ ./price_per_meal.sh --months 2022-09,2022-11,2023-03,2023-09,2023-11,2024-03 ledger_2025.dat
      months values shifted mom_change discount
1 2022-09-01  152.7   154.0  0.9915584     0.90
2 2022-11-01  154.0   155.3  0.9916291     0.91
3 2023-03-01  155.3   158.5  0.9798107     0.91
4 2023-09-01  158.5   158.8  0.9981108     0.93
5 2023-11-01  158.8   159.8  0.9937422     0.94
6 2024-03-01  159.8   169.8  0.9411072     0.94
7 2026-08-01  169.8   169.8  1.0000000     1.00
Total: $3844.57
182.00 days in timespan
Daily total: $21.12
Meals/day: 4
Price per meal: $5.28
```

Not bad at all--$5.28 per meal is going to be pretty hard to beat. And it's not
like I'm putting back Kraft Dinner day in and day out--these are generally
nutritious, balanced dishes that I'm cooking (mostly vegatarian, which helps
with cost, although there's the odd meat-based dish and ample protein
supplementation on top of this). For reference, here's what a typical day from
that timeframe looks like:

![Image taken from my MacroFactor log, 2024-03-05]({{ "/assets/images/food_log.png" | remove_first: '/' | absolute_url }}){:.center-image}

Let's now take a look at what the aforementioned meal service providers are
offering. Note that, up until now, I've been using "meal" to refer to a plate of
food, while the service providers use "serving" for this instead. Apologies for
the confusion. I've provided pricing info, pulled directly from their websites,
in the table below. The smallest order sizes (in servings/wk; capped at a 21
serving per week ceiling) yielding the lowest per-serving price were used. In
other words, I selected the smallest order size required to get into the lowest
possible pricing tier. The reason for the 21 serving per week ceiling is that in
practice I wouldn't forgo my entire grocery budget for meal kits: I'd at minimum
still be buying snacks and breakfast items from the store. I consider that to be
equivalent to one serving's worth of calories per day, leaving me with 21 (`4 *
7 * 3/4`) "full servings" available for substitution. It's hard to gauge exactly
how large of a weekly order would be sufficient, as I don't know what the
average per-serving calorie count is for each service. Without that knowledge, I
can't determine exactly how many meals would be required to fill my weekly
caloric budget of 22,400 kcal. But for the sake of convenience, I'll assume that
one serving of a home-cooked meal is equivalent to one serving from a meal
service.

| Service    | Type          | Servings/wk | $/serving |
| ---------- | ------------- | ----------: | --------: |
| Factor     | Prepared      | 8           | 14.49     |
| Goodfood   | Semi-Prepared | 16          | 12.15     |
| HelloFresh | Semi-Prepared | 20          | 9.99      |

> **/?\\**{:#mono} Shipping is excluded from the $/serving figures due to the
> differing order sizes. As far as I'm aware, these prices are given without any
> promotional discounts applied.
{:.aside}

No huge surprises here, except for maybe the $2+ dollar spread between Goodfood
and HelloFresh: I'd expected that to be a bit tighter.

Some quick, back-of-the-napkin math: I almost always split up an entire week's
worth of food into two shopping runs, so that's 14 servings per trip. I'm a
quick shopper and have always lived within walking distance of the grocery
store, so my trips, including transit time, are generally no more than an hour.
So that's roughly 0.071 hr/serving (or 4.28 min/serving) dedicated to acquiring
the food. Let's suppose I still make one run to the grocery store per week for
snacks and whatnot. The time saved now becomes 0.048 hr/full serving (`1 hr/trip
/ (28 servings/trip * 3 full servings / 4 servings)`). The median "full meal" in
my recipe book serves 4. With combined cooking plus cleaning taking around 1.5
hr/full meal, that's 0.375 hr/full serving. Let's also assume 10 minutes spent
planning each meal (e.g., taking stock of the fridge/pantry and putting a list
together), which amounts to an additional 0.056 hr/full serving of overhead.
Altogether, that's approximately 0.478 hr/full serving, or 29 min/full serving.

| Service    | Time Savings (hr) | Time Premium ($) | Hourly rate ($/hr) |
| ---------- | ----------------: | ---------------: | -----------------: |
| Factor     | 0.478             | 9.21             | 19.26              |
| Goodfood   | 0.228             | 6.87             | 30.11              |
| HelloFresh | 0.228             | 4.71             | 20.64              |

> **/?\\**{:#mono} In addition to the combined shopping plus overhead time
> savings of 0.103 hr/full serving associated with Goodfood and HelloFresh, I've
> also added a generous 0.5 hr/full meal (0.125 hr/full serving) time saving
> under the assumption that their recipes are probably going to be quicker to
> cook than the recipes I currently make.
{:.aside}

Wow, now this I wasn't expecting. Factor, despite being the most expensive
service in absolute terms by a wide margin, actually costs less than both other
options when time savings are taken into account. And all three are under my
equivalent hourly rate as a salaried employee. In theory, this means that it
would be economically inefficient to *not* be using such a service; however, in
reality there's the indivisibility of labour problem: work is not divided into
infinitesimally small units and thus I cannot simply exchange 15 minutes of my
time for the equivalent amount of cash (that won't stop me from assigning value
to my free time, though :D). Nevertheless, it is most certainly, if I may,
*food* for thought. I will see myself to the door now.

Thank you for reading this episode of How to Eat Like Me.
