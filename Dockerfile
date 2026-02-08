FROM python:3.11-slim

ARG FREQTRADE_BRANCH=develop

RUN apt-get update && apt-get install -y \
    git \
    wget \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
    freqtrade@git+https://github.com/freqtrade/freqtrade.git@${FREQTRADE_BRANCH}

WORKDIR /freqtrade

COPY user_data/ /freqtrade/user_data/

ENV TZ=Europe/Prague
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

CMD ["freqtrade"]
