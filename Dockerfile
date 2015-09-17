FROM quay.io/sorah/rbenv:2.2

RUN mkdir -p /tmp/lib/adchpasswd /app
ADD Gemfile /tmp/
ADD adchpasswd.gemspec /tmp/

ADD lib/adchpasswd/version.rb /tmp/lib/adchpasswd/version.rb
WORKDIR /tmp
RUN bundle install --jobs 2 --retry 2 --without development:test

ADD . /app
RUN cp -rv Gemfile* .bundle /app/
WORKDIR /app

ENV RACK_ENV production

CMD ["bundle", "exec", "unicorn"]
