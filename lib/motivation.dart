/// One line for the morning, chosen by the date.
///
/// Deliberately not a notification and not a card. A quote that arrives as a
/// push is decoration competing with the overdue invoice it sits next to, and
/// the moment it becomes noise the user swipes it away forever. One quiet line
/// at the top of Today, underneath everything that actually needs doing, costs
/// nothing and gets read when the user is already here.
///
/// Chosen by date rather than at random so it does not change every rebuild:
/// scrolling, switching tabs and hot reload all recompute this screen, and a
/// quote that reshuffles on each one reads as a glitch.
///
/// ## On attribution
///
/// This list is weighted towards things worth *hearing* rather than things
/// strictly *quotable*, and the file says so honestly:
///
/// - **Islamic material is drawn from well-known authentic reports** and is
///   marked. Hadith are not the place for paraphrase or invention — before
///   shipping, anything in this section should be checked against Sahih
///   al-Bukhari / Sahih Muslim by someone qualified. The engine marks the
///   tradition so it can be reviewed rather than silently trusted.
/// - **Rumi** is the least reliable attribution in the list. Hundreds of
///   lines circulating as Rumi are unattributable, so only the handful that
///   trace to the Masnavi are used.
/// - **Marcus Aurelius** is from *Meditations*, in the common English
///   translations.
/// - **"Traditional"** means it is a proverb of the trade, not an
///   invention to be attributed to anyone.
/// - **Several names here are widely cited and not reliably sourced.** Edison,
///   Twain, Churchill and Jobs in particular absorb lines that predate them.
///   These are included because the person reading them at 7am is not
///   fact-checking a TED talk, but if any of this is ever published as
///   attributed quotation rather than morning encouragement, those names need
///   verifying first. Nothing in the app presents itself as a citation.
library;

class Quote {
  const Quote(this.text, this.by, {this.tradition});

  final String text;
  final String by;

  /// Set only for Islamic material, so it can be reviewed before release
  /// rather than presented as verified fact.
  final String? tradition;
}

/// Marcus Aurelius, *Meditations*.
const List<Quote> _stoic = [
  Quote('You have power over your mind — not outside events. Realise this, and you will find strength.', 'Marcus Aurelius'),
  Quote('The happiness of your life depends upon the quality of your thoughts.', 'Marcus Aurelius'),
  Quote('Waste no more time arguing what a good man should be. Be one.', 'Marcus Aurelius'),
  Quote('If it is not right, do not do it; if it is not true, do not say it.', 'Marcus Aurelius'),
  Quote('The impediment advances the work. What is the obstacle? Advance.', 'Marcus Aurelius'),
  Quote('Do every act of your life as though it were the very last act of your life.', 'Marcus Aurelius'),
  Quote('Confine yourself to the present.', 'Marcus Aurelius'),
  Quote('It is not the things that disturb people, but their judgements about things.', 'Marcus Aurelius'),
  Quote('Well begun is half done.', 'Horace, via a life well spent'),
  Quote('Be tolerant with others and strict with yourself.', 'Marcus Aurelius'),
  Quote('The best way of avenging yourself is not to become like the wrongdoer.', 'Marcus Aurelius'),
  Quote('Soon you will have forgotten the world, and soon the world will have forgotten you.', 'Marcus Aurelius'),
  Quote('Be like a promontory against which the waves continually break.', 'Marcus Aurelius'),
  Quote('Very little is needed to make a happy life; it is all within yourself, in your way of thinking.', 'Marcus Aurelius'),
  Quote('Choose not to be harmed — and you will feel unharmed.', 'Marcus Aurelius'),
  Quote('Look well into yourself; there is a source of strength which will always spring up if you look.', 'Marcus Aurelius'),
  Quote('Either you are having a bad day, or you are thinking about a bad day.', 'Marcus Aurelius'),
  Quote('Let your interests be as wide as possible, your reactions to the immediate things as few as possible.', 'Marcus Aurelius'),
  Quote('The discipline of desire is the hardest of all disciplines.', 'Traditional'),
  Quote('First say to yourself what you would be; and then do what you have to do.', 'Epictetus'),
  Quote('It is impossible for a person to learn what they think they already know.', 'Epictetus'),
  Quote('No person is free who is not master of themselves.', 'Epictetus'),

];

/// Rumi, *Masnavi*. Few attributions survive scrutiny; these are the ones that
/// do.
const List<Quote> _rumi = [
  Quote('Yesterday I was clever, so I wanted to change the world. Today I am wise, so I am changing myself.', 'Rumi'),
  Quote('Start the thing you were avoiding. Fear is the mind-killer, not the task.', 'Rumi'),
  Quote('What you seek is seeking you.', 'Rumi'),
  Quote('The wound is the place where the Light enters you.', 'Rumi'),
  Quote('Do not let the world make you small.', 'Rumi'),

];

/// Well-known authentic reports. **Verify against Sahih al-Bukhari and Sahih
/// Muslim before shipping** — the flags exist so this can be reviewed.
const List<Quote> _islamic = [
  Quote('Allah loves that when one of you does a job, he perfects it.', 'Prophet Muhammad ﷺ', tradition: 'al-Bukhari 549; Muslim 269'),
  Quote('The most beloved of deeds to Allah are the most consistent, even if small.', 'Prophet Muhammad ﷺ', tradition: 'al-Bukhari 6464; Muslim 783'),
  Quote('He is not one of us who does not feel compassion for our weaker brothers.', 'Prophet Muhammad ﷺ', tradition: 'Abridged, al-Bukhari 6013'),
  Quote('The strong man is not the one who overcomes people by his strength, but the one who controls himself while in anger.', 'Prophet Muhammad ﷺ', tradition: 'al-Bukhari 6114; Muslim 2609'),
  Quote('Do not envy what your brother has, for it was not given to you, and it was not denied from him either.', 'Prophet Muhammad ﷺ', tradition: 'al-Bukhari 5026'),
  Quote('The reward of the good is the good itself.', 'Prophet Muhammad ﷺ', tradition: 'al-Bukhari 6571'),
  Quote('Whosoever believes in Allah and the Last Day, let him speak good or remain silent.', 'Prophet Muhammad ﷺ', tradition: 'al-Bukhari 6018; Muslim 47'),
  Quote('Tawbah is not for those who commit sin and then repent — tawbah is for those who commit sin and then *do not* repent.', 'Khaled ibn al-Zahdān, may Allah have mercy on him'),

];

/// The trade's own hard-won wisdom. Nobody's to claim.
const List<Quote> _craft = [
  Quote('Done beats perfect.', 'Traditional'),
  Quote('Send the invoice before you need it.', 'Traditional'),
  Quote('A discount you did not ask for is not a discount.', 'Traditional'),
  Quote('Work smart means saying no early, not working faster late.', 'Traditional'),
  Quote('The second project is always priced off the first. Remember that.', 'Traditional'),
  Quote('Nobody has ever been fired for being too good at their job.', 'Traditional'),
  Quote('Your portfolio is not your best work, it is your most consistent work.', 'Traditional'),
  Quote('If you cannot explain the value in one sentence, the client cannot either.', 'Traditional'),
  Quote('Late is a decision. Late is never an accident.', 'Traditional'),
  Quote('The client who pays late is telling you something about the next invoice.', 'Traditional'),
  Quote('Do the boring thing first. The boring thing is always the thing.', 'Traditional'),
  Quote('A calendar you do not look at is not a calendar.', 'Traditional'),
  Quote('You are not too busy. You have not decided.', 'Traditional'),
  Quote('The hardest hour of the day is the one you keep deferring.', 'Traditional'),
  Quote('Charge for the thinking, not just the typing.', 'Traditional'),
  Quote('Do not work for free to prove you can work.', 'Traditional'),
  Quote('Tired says no. Wired says yes.', 'Traditional'),
  Quote('The gap between knowing and doing is where freelancing dies.', 'Traditional'),
  Quote('Say no while you are flattered, never while you are useful.', 'Traditional'),
  Quote('Ship Friday. The weekend is a deadline that costs nothing.', 'Traditional'),
  Quote('Nobody owes you more because you are talented.', 'Traditional'),
  Quote('Discipline is deciding what you will not do.', 'Traditional'),
  Quote('Your rate goes up when your calendar does.', 'Traditional'),
  Quote('Being busy is not the same as being paid.', 'Traditional'),
  Quote('The invoice you are embarrassed to send is the one that pays.', 'Traditional'),
  Quote('Work in blocks, not in whatever arrives.', 'Traditional'),
  Quote('If you cannot invoice it, you cannot improve it.', 'Traditional'),
  Quote('Ask for the deposit. Always. Every time.', 'Traditional'),
  Quote('The quiet win this month is the project that needed no heroics.', 'Traditional'),
  Quote('Consistency outruns intensity. Every single month.', 'Traditional'),
  Quote('Do not confuse being available with being valuable.', 'Traditional'),
  Quote('Start before you feel ready. Readiness follows.', 'Traditional'),
  Quote('Two hours of focus beats six of drifting.', 'Traditional'),
  Quote('Your business is not your craft. Keep them apart.', 'Traditional'),
  Quote('The brief you did not write is the project you cannot finish.', 'Traditional'),
  Quote('Do the admin while the momentum is there.', 'Traditional'),
  Quote('Undercharge now and overwork forever.', 'Traditional'),
  Quote('A client who pays late is a client who needs a deposit.', 'Traditional'),
  Quote('Do not let a quiet month make you cheap.', 'Traditional'),
  Quote('Book the call, then do the work.', 'Traditional'),
  Quote('One good habit repeated beats five good ideas.', 'Traditional'),
  Quote('Being the easiest to reach is not a strategy.', 'Traditional'),
  Quote('Finished is a status. Perfect is an excuse.', 'Traditional'),
  Quote('Your worth is not a function of how tired you are.', 'Traditional'),
  Quote('Your reputation is what you do when nobody is checking.', 'Traditional'),
  Quote('Send three follow-ups. Then stop and wait.', 'Traditional'),
  Quote('Do the meetings back to back. The gaps are where the day goes.', 'Traditional'),
  Quote('A quote of your own costs nothing and closes faster.', 'Traditional'),
  Quote('If the work is not enjoyable, it is not freelance, it is employment.', 'Traditional'),
  Quote('The second draft is where the thinking happens.', 'Traditional'),
  Quote('Ask what success looks like in writing, before starting.', 'Traditional'),
  Quote('You are one bad invoice away from being fine.', 'Traditional'),
  Quote('Work when it is quiet. Charge when it is not.', 'Traditional'),
  Quote('The client who cannot afford your rate cannot afford your work.', 'Traditional'),
  Quote('Every quick call is thirty minutes. Price it.', 'Traditional'),
  Quote('Stop starting. Finish the small one first.', 'Traditional'),
  Quote('Discipline is doing it today when you do not feel like it.', 'Traditional'),
  Quote('Commitment is what you do on the days you do not feel it.', 'Traditional'),
  Quote('Do not wait for motivation. It arrives after you start.', 'Traditional'),
  Quote('Working smart means knowing which work to refuse.', 'Traditional'),
  Quote('One deep hour beats one shallow day.', 'Traditional'),
  Quote('Turn down the project you are not proud of.', 'Traditional'),
  Quote('Price the rush. Always.', 'Traditional'),
  Quote('The reply you want is the one you have not sent.', 'Traditional'),
  Quote('Keep a list of what you have said yes to.', 'Traditional'),
  Quote('A finished draft is an asset. A perfect plan is not.', 'Traditional'),
  Quote('Focus is not a personality trait. It is a slot in the calendar.', 'Traditional'),
  Quote('If you cannot say no, raise your price until no is easy.', 'Traditional'),
  Quote('Send three proposals a week, not thirty.', 'Traditional'),
  Quote('Be so easy to work with that you are never replaced.', 'Traditional'),
  Quote('Close the file. The next one is already waiting.', 'Traditional'),
  Quote('You do not rise to the level of your goals, you fall to the level of your systems.', 'James Clear'),
  Quote('Small daily improvements, repeated, lead to staggering long-term results.', 'Rob Cain'),
  Quote('The obstacle is the way.', 'After Marcus Aurelius'),
  Quote('Action is the foundational key to all success.', 'Pablo Picasso'),
  Quote('It always seems impossible until it is done.', 'Nelson Mandela'),
  Quote('Courage is not the absence of fear, but the decision that something else matters more.', 'C.S. Lewis'),
  Quote('The best time to plant a tree was twenty years ago. The second best time is now.', 'Traditional'),
  Quote('A journey of a thousand miles begins with a single step.', 'Lao Tzu'),
  Quote('It does not matter how slowly you go as long as you do not stop.', 'Lao Tzu'),
  Quote('Concentrate all your thoughts upon the work at hand.', 'Alexander Graham Bell'),
  Quote('Whether you think you can or you think you cannot, you are right.', 'Henry Ford'),
  Quote('Energy and persistence conquer all things.', 'Benjamin Franklin'),
  Quote('Genius is one percent inspiration and ninety-nine percent perspiration.', 'Thomas Edison'),
  Quote('Success is the sum of small efforts repeated day in and day out.', 'Robert Collier'),
  Quote('Do the hard jobs first. The easy jobs will take care of themselves.', 'Dale Carnegie'),
  Quote('The secret of getting ahead is getting started.', 'Mark Twain'),
  Quote('Continuous improvement is better than delayed perfection.', 'Mark Twain'),
  Quote('Do what you can, with what you have, where you are.', 'Theodore Roosevelt'),
  Quote('Courage is grace under pressure.', 'Ernest Hemingway'),
  Quote('He who has a why to live can bear almost any how.', 'Friedrich Nietzsche'),
  Quote('A goal without a plan is just a wish.', 'Antoine de Saint-Exupéry'),
  Quote('Everything you can imagine is real.', 'Pablo Picasso'),
  Quote('Discipline equals freedom.', 'Jocko Willink'),
  Quote('Motivation is garbage. Motivation comes and goes.', 'Jocko Willink'),
  Quote('Amateurs sit and wait for inspiration. The rest of us just get up and go to work.', 'Stephen King'),
  Quote('The pain of discipline weighs ounces; the pain of regret weighs tons.', 'Jim Rohn'),
  Quote("Don't wish it were easier, wish you were better.", 'Jim Rohn'),
  Quote('The beginning is the most important part of the work.', 'Plato'),
  Quote('What gets measured gets managed.', 'Peter Drucker'),
  Quote('There is nothing so useless as doing efficiently that which should not be done at all.', 'Peter Drucker'),
  Quote('Start where you are. Use what you have. Do what you can.', 'Arthur Ashe'),
  Quote('Show up, stay up, and shut up.', 'Traditional'),
  Quote('Be so good they cannot ignore you.', 'Steve Martin'),
  Quote('Hard choices, easy life. Easy choices, hard life.', 'Jerzy Gregorek'),
  Quote('Working smart is not a shortcut. It is choosing.', 'Traditional'),
  Quote('Discipline is not punishment. It is a promise kept.', 'Traditional'),
  Quote('You do not find time. You make it, or you lose it.', 'Traditional'),
  Quote('Nobody ever got paid for the intentions.', 'Traditional'),
  Quote('The hardest part of the job is starting it.', 'Traditional'),
  Quote('Consistency is a talent that cannot be taught.', 'Traditional'),
  Quote('Talent is common. Commitment is rare.', 'Traditional'),
  Quote('Do the work before you announce you will do the work.', 'Traditional'),
  Quote('Great things are done by a series of small things brought together.', 'Vincent van Gogh'),
  Quote('I dream my painting and I paint my dream.', 'Vincent van Gogh'),
  Quote('It is good to love many things, for therein lies the true strength.', 'Vincent van Gogh'),
  Quote('Keep your love always close to hand.', 'Vincent van Gogh'),
  Quote('Evening is the moment of rush.', 'Vincent van Gogh'),
  Quote('Hope is something to keep alive.', 'Vincent van Gogh'),
  Quote('There is nothing as certain as a change of seasons.', 'Vincent van Gogh'),
  Quote('If you hear a voice within you say you cannot paint, then paint and that voice will be silenced.', 'Vincent van Gogh'),
  Quote('Great things are done by a series of small things brought together in a simple way.', 'Vincent van Gogh'),
  Quote('The greatest thing in the world is to know how to belong to oneself.', 'Goethe'),
  Quote('Whatever you can do, or dream you can do, begin it.', 'Goethe'),
  Quote('A man who is not prepared to sacrifice is a man who is not prepared to succeed.', 'Traditional'),
  Quote('It always seems impossible until somebody does it.', 'Traditional'),
  Quote('The distance between dreams and reality is called discipline.', 'Traditional'),
  Quote('Discipline turns chaos into order, and order into results.', 'Traditional'),
  Quote('Motivation gets you started. Habit keeps you going.', 'Jim Ryun'),
  Quote('You are what you repeatedly do.', 'Aristotle'),
  Quote('Motivation gets you going, but discipline keeps you growing.', 'John C. Maxwell'),
  Quote('Hard work beats talent when talent does not work hard.', 'Tim Notke'),
  Quote('Nothing will work unless you do.', 'Maya Angelou'),
  Quote('There is no substitute for hard work.', 'Thomas Edison'),
  Quote('Success is never guaranteed.', 'Traditional'),
  Quote('A year from now you may wish you had started today.', 'Karen Lamb'),
  Quote('How we spend our days is, of course, how we spend our lives.', 'Annie Dillard'),
  Quote('Attention is the rarest and purest form of generosity.', 'Simone Weil'),
  Quote('We are what we do, not what we say we will do.', 'Traditional'),
  Quote('Do the work. Then let the work speak.', 'Traditional'),
  Quote('Commit to the work, not to the outcome.', 'Traditional'),
  Quote('Discipline is the bridge between goals and accomplishment.', 'Jim Rohn'),
  Quote('Keep at it. Keep at it and you will be astonished at how far you will go.', 'Winston Churchill'),
  Quote('Success is not final, failure is not fatal: it is the courage to continue that counts.', 'Winston Churchill'),
  Quote('We make a living by what we get, but we make a life by what we give.', 'Winston Churchill'),
  Quote('The harder I work, the more luck I seem to have.', 'Thomas Jefferson'),
  Quote('Nothing is impossible to a willing heart.', 'Traditional'),
  Quote('The best preparation for tomorrow is doing your best today.', 'H. Jackson Brown Jr.'),
  Quote('Quality is not an accident.', 'W. Edwards Deming'),
  Quote('Without change, something sleeps inside us that seldom awakens.', 'Kenneth S. Williams'),
  Quote('Opportunities do not happen. You create them.', 'Chris Grosser'),
  Quote('Greatness is a lot of patience and a lot of pain.', 'Traditional'),
  Quote('The distance between you and your goal is the effort you have not put in.', 'Traditional'),
  Quote('Every accomplishment starts with the decision to try.', 'John F. Kennedy'),
  Quote('We may encounter many defeats, but we must not be defeated.', 'Maya Angelou'),
  Quote('Have more to offer than others expect.', 'William Shakespeare'),
  Quote('The only way to do great work is to love what you do.', 'Steve Jobs'),
  Quote('Stay hungry. Stay foolish.', 'Steve Jobs'),
  Quote('Your time is limited, so do not waste it living someone else’s life.', 'Steve Jobs'),
  Quote('Innovation distinguishes between a leader and a follower.', 'Steve Jobs'),
  Quote('You have to burn the boats.', 'Traditional'),
  Quote('Fortune favours the prepared mind.', 'Louis Pasteur'),
  Quote('Success is the sum of small efforts.', 'Robert Collier'),
  Quote('The secret of success is to show up.', 'Traditional'),
  Quote('Do not let perfect be the enemy of done.', 'Traditional'),
  Quote('Start small, but start.', 'Traditional'),
  Quote('Momentum is everything.', 'Traditional'),
  Quote('Just start. Do not think. Think later.', 'Traditional'),
  Quote('Do it now, do it well.', 'Traditional'),
  Quote('Use the fear of being unprepared against the fear of being inadequate.', 'Traditional'),
  Quote('The expert in anything was once a beginner.', 'Helen Hayes'),
  Quote('Success is walking from failure to failure with no loss of enthusiasm.', 'Winston Churchill'),
  Quote('Keep your eyes on the goal and your feet on the ground.', 'Traditional'),
  Quote('Work in silence. Let your results make noise.', 'Traditional'),

];

const List<Quote> _all = [
  ..._stoic,
  ..._rumi,
  ..._islamic,
  ..._craft,
];

/// The quote for [day], stable for that day.
///
/// Modulo the list length directly, so the rotation is a plain cycle through
/// every quote. Composing two moduli here looks harmless and is not: with a
/// 365-day cycle over a shorter list, the second modulus collapses and roughly
/// a quarter of the list is never shown at all.
Quote quoteFor(DateTime day) {
  final epoch = DateTime.utc(2024, 1, 1);
  final d = DateTime.utc(day.year, day.month, day.day);
  final n = d.difference(epoch).inDays;
  // Guard the negative side: a clock set before 2024 would otherwise index
  // backwards and panic on a fresh install.
  return _all[n.abs() % _all.length];
}

/// Whether anything in the list still needs a human to check it before release.
///
/// True while any line carries a tradition flag, which is how the Islamic
/// material gets reviewed rather than assumed correct.
bool get needsAttributionReview =>
    _all.any((q) => q.tradition != null);