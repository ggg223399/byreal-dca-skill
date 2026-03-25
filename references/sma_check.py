#!/usr/bin/env python3
"""
Moving-average market regime check for Byreal DCA.

Usage:
    python3 sma_check.py SOL
    python3 sma_check.py SOL --ma 50
    python3 sma_check.py BTC --ma 200

Output (JSON):
    {"token": "SOL", "ticker": "SOL-USD", "price": 148.20, "ma": 142.50, "ma_window": 200, "signal": "above"}

Signals:
    above       — price > MA(window)
    below       — price < MA(window)
    unavailable — download/data issue → caller fallback
"""

import argparse
import json
import sys

import yfinance as yf

TICKERS = {
    # Crypto
    "SOL": "SOL-USD",
    "BTC": "BTC-USD",
    "CBBTC": "BTC-USD",
    "ETH": "ETH-USD",
    "WETH": "ETH-USD",
    # Gold
    "XAUT0": "GC=F",
    "XAU": "GC=F",
    # xStock (Byreal DEX token symbol → yfinance ticker)
    "SPYX": "SPY",
    "SPY": "SPY",
    "QQQX": "QQQ",
    "QQQ": "QQQ",
    "NVDAX": "NVDA",
    "NVDA": "NVDA",
    "GOOGLX": "GOOGL",
    "GOOGL": "GOOGL",
    "TSLAX": "TSLA",
    "TSLA": "TSLA",
    "AMZNX": "AMZN",
    "AMZN": "AMZN",
    "CRCLX": "CRCL",
    "CRCL": "CRCL",
    "COINX": "COIN",
    "COIN": "COIN",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check price vs moving average.")
    parser.add_argument("token", nargs="?", default="SOL")
    parser.add_argument("--ma", type=int, default=200, dest="ma_window")
    return parser.parse_args()


def unavailable(token: str, ticker: str, ma_window: int, error: str) -> int:
    print(
        json.dumps(
            {
                "token": token,
                "ticker": ticker,
                "ma_window": ma_window,
                "signal": "unavailable",
                "error": error,
            }
        )
    )
    return 0


def main() -> int:
    args = parse_args()
    token = args.token.upper()
    ticker = TICKERS.get(token, token)
    ma_window = args.ma_window

    if ma_window <= 0:
        return unavailable(token, ticker, ma_window, "invalid_ma_window")

    try:
        data = yf.download(ticker, period="1y", progress=False)
        closes = data["Close"].squeeze().dropna()
    except Exception:
        return unavailable(token, ticker, ma_window, "download_failed")

    if len(closes) < ma_window:
        return unavailable(token, ticker, ma_window, "insufficient_data")

    try:
        price = float(closes.iloc[-1])
        moving_average = float(closes.rolling(ma_window).mean().iloc[-1])
    except Exception:
        return unavailable(token, ticker, ma_window, "calculation_failed")

    print(
        json.dumps(
            {
                "token": token,
                "ticker": ticker,
                "price": round(price, 2),
                "ma": round(moving_average, 2),
                "ma_window": ma_window,
                "signal": "above" if price > moving_average else "below",
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
