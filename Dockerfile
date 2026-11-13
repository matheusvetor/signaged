FROM ruby:2.6.3

WORKDIR /app

ENV BUNDLE_FROZEN=true

COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 2.4.22 --no-document \
    && bundle _2.4.22_ install

COPY .rspec ./
COPY bin/ bin/
COPY lib/ lib/
COPY spec/ spec/

CMD ["bundle", "_2.4.22_", "exec", "rspec"]
