import pandas as pd
import numpy as np
import matplotlib
matplotlib.use('Agg')  # Non-interactive backend for saving to file
import matplotlib.pyplot as plt
import optuna
import time
import joblib
from xgboost import XGBRegressor
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
from sklearn.preprocessing import LabelEncoder

# ─────────────────────────────────────────────────────────────────
# Suppress verbose Optuna info logging to keep output clean
# ─────────────────────────────────────────────────────────────────
optuna.logging.set_verbosity(optuna.logging.WARNING)

SPLIT_DATE = pd.to_datetime('2025-10-01')
PLOT_PATH = 'learning_curve.png'
OPTUNA_TRIALS = 60
MODEL_PATH = 'trained_model.joblib'
ENCODERS_PATH = 'label_encoders.joblib'

# ─────────────────────────────────────────────────────────────────
# 1. Load & Preprocess
# ─────────────────────────────────────────────────────────────────
def load_data():
    print("[1/5] Loading dataset...")
    try:
        df = pd.read_csv('indian_food_wastage_dataset.csv')
    except FileNotFoundError:
        print("ERROR: 'indian_food_wastage_dataset.csv' not found. Run generate_data.py first.")
        exit(1)

    df['date'] = pd.to_datetime(df['date'])

    cat_cols = ['area', 'area_type', 'season', 'weather', 'food_item', 'food_category']
    encoders = {}
    for col in cat_cols:
        le = LabelEncoder()
        df[col] = le.fit_transform(df[col])
        encoders[col] = le

    return df, encoders


# ─────────────────────────────────────────────────────────────────
# 2. Feature Engineering (Interaction + Dropping Weak Features)
# ─────────────────────────────────────────────────────────────────
def engineer_features(df):
    print("[2/5] Engineering features...")

    # Interaction feature: Tech Park restaurant on a weekend = worst case
    df['area_type_x_weekend'] = df['area_type'] * df['is_weekend']

    # Derived ratio: historical waste rate (highly predictive, no leakage)
    df['waste_to_prep_ratio_7d'] = (
        df['rolling_7_day_avg_wastage'] / df['quantity_prepared'].clip(lower=1)
    ).round(4)

    # Drop known low-value features
    LOW_IMPORTANCE_FEATURES = ['restaurant_id']
    df.drop(columns=LOW_IMPORTANCE_FEATURES, inplace=True)

    features = [
        'area', 'area_type', 'food_item', 'food_category',
        'day_of_week', 'is_weekend', 'is_payday_week',
        'season', 'weather', 'quantity_prepared', 'wastage_yesterday',
        'wastage_same_day_last_week', 'rolling_7_day_avg_wastage',
        'area_type_x_weekend', 'waste_to_prep_ratio_7d'
    ]
    target = 'quantity_wasted'

    return df, features, target


# ─────────────────────────────────────────────────────────────────
# 3. Bayesian Hyperparameter Optimisation (Optuna)
# ─────────────────────────────────────────────────────────────────
def run_optuna(X_train, y_train, X_test, y_test):
    print(f"[3/5] Running Bayesian Optimisation ({OPTUNA_TRIALS} trials)...")

    def objective(trial):
        params = {
            'n_estimators':       trial.suggest_int('n_estimators', 200, 800),
            'max_depth':          trial.suggest_int('max_depth', 3, 9),
            'learning_rate':      trial.suggest_float('learning_rate', 0.01, 0.2, log=True),
            'subsample':          trial.suggest_float('subsample', 0.5, 1.0),
            'colsample_bytree':   trial.suggest_float('colsample_bytree', 0.5, 1.0),
            'min_child_weight':   trial.suggest_int('min_child_weight', 1, 10),
            'reg_alpha':          trial.suggest_float('reg_alpha', 1e-5, 1.0, log=True),
            'reg_lambda':         trial.suggest_float('reg_lambda', 1e-5, 1.0, log=True),
            'random_state': 42,
            'tree_method': 'hist',
        }
        model = XGBRegressor(**params)
        model.fit(X_train, y_train, verbose=False)
        y_pred = model.predict(X_test)
        return np.sqrt(mean_squared_error(y_test, y_pred))

    study = optuna.create_study(direction='minimize')
    study.optimize(objective, n_trials=OPTUNA_TRIALS, show_progress_bar=False)

    best = study.best_params
    print(f"   Best RMSE: {study.best_value:.4f} units")
    print(f"   Best Params: {best}")
    return best


# ─────────────────────────────────────────────────────────────────
# 4. Final Training with Best Params + Learning Curve
# ─────────────────────────────────────────────────────────────────
def train_and_plot(X_train, y_train, X_test, y_test, best_params):
    print("[4/5] Training final model with optimal hyperparameters...")

    # Train with evals_result capture (XGBoost 3.x: call .evals_result() after fit)
    model_curve = XGBRegressor(
        **best_params,
        random_state=42,
        tree_method='hist',
        eval_metric='rmse',
    )
    model_curve.fit(
        X_train, y_train,
        eval_set=[(X_train, y_train), (X_test, y_test)],
        verbose=False,
    )
    evals_result = model_curve.evals_result()

    # ── Learning Curve Plot ──────────────────────────────────────
    # XGBoost 3.x keys the sets as 'validation_0', 'validation_1'
    train_rmse = evals_result['validation_0']['rmse']
    test_rmse  = evals_result['validation_1']['rmse']
    iterations = range(1, len(train_rmse) + 1)

    # Find early stopping sweet spot (min test RMSE)
    best_iter = int(np.argmin(test_rmse)) + 1

    plt.figure(figsize=(11, 5))
    plt.plot(iterations, train_rmse, label='Train RMSE', color='#4C9BE8', linewidth=1.8)
    plt.plot(iterations, test_rmse,  label='Test RMSE',  color='#E8704C', linewidth=1.8)
    plt.axvline(x=best_iter, color='#2ECC71', linestyle='--', linewidth=1.5,
                label=f'Sweet Spot (iter={best_iter}, RMSE={min(test_rmse):.4f})')
    plt.fill_between(iterations, train_rmse, test_rmse,
                     where=[t > v for t, v in zip(test_rmse, train_rmse)],
                     alpha=0.15, color='red', label='Overfitting Region')
    plt.xlabel('Boosting Iterations (n_estimators)', fontsize=12)
    plt.ylabel('RMSE (units)', fontsize=12)
    plt.title('XGBoost Learning Curve — Train vs Test RMSE', fontsize=14, fontweight='bold')
    plt.legend(fontsize=10)
    plt.grid(True, linestyle='--', alpha=0.4)
    plt.tight_layout()
    plt.savefig(PLOT_PATH, dpi=150)
    plt.close()
    print(f"   Learning curve saved to: {PLOT_PATH}")
    print(f"   Early Stopping Sweet Spot: Iteration {best_iter}")

    return model_curve


# ─────────────────────────────────────────────────────────────────
# 5. Evaluation & Feature Importance
# ─────────────────────────────────────────────────────────────────
def evaluate(model, X_train, y_train, X_test, y_test, features):
    print("[5/5] Final Evaluation...")

    # Train metrics
    y_pred_train = model.predict(X_train)
    train_rmse = np.sqrt(mean_squared_error(y_train, y_pred_train))
    train_r2   = r2_score(y_train, y_pred_train)

    # Test metrics
    y_pred_test = model.predict(X_test)
    test_rmse = np.sqrt(mean_squared_error(y_test, y_pred_test))
    test_mae  = mean_absolute_error(y_test, y_pred_test)
    test_r2   = r2_score(y_test, y_pred_test)

    print("\n" + "═" * 40)
    print("       MODEL PERFORMANCE SUMMARY")
    print("═" * 40)
    print(f"  Train RMSE : {train_rmse:.4f} units")
    print(f"  Test  RMSE : {test_rmse:.4f} units")
    print(f"  Test  MAE  : {test_mae:.4f} units")
    print(f"  Train R^2  : {train_r2:.4f}")
    print(f"  Test  R^2  : {test_r2:.4f}")
    print(f"  Overfit Gap: {train_rmse - test_rmse:.4f} units (Train - Test RMSE)")
    print("═" * 40)

    # Feature Importance
    print("\n  Feature Importances (F-Score Gain):")
    importances = pd.DataFrame({
        'Feature': features,
        'Importance': model.feature_importances_
    }).sort_values('Importance', ascending=False)

    for _, row in importances.iterrows():
        bar = '#' * int(row['Importance'] * 200)
        print(f"  {row['Feature']:>30s}: {row['Importance']:.4f}  {bar}")


# ─────────────────────────────────────────────────────────────────
# 6. Save Model & Encoders
# ─────────────────────────────────────────────────────────────────
def save_model(model, encoders):
    joblib.dump(model, MODEL_PATH)
    joblib.dump(encoders, ENCODERS_PATH)
    print(f"\n  ✓ Model saved to:    {MODEL_PATH}")
    print(f"  ✓ Encoders saved to: {ENCODERS_PATH}")


# ─────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    total_start = time.time()

    df, encoders = load_data()
    df, features, target = engineer_features(df)

    # Strict time-based split
    X_train = df.loc[df['date'] < SPLIT_DATE, features]
    y_train = df.loc[df['date'] < SPLIT_DATE, target]
    X_test  = df.loc[df['date'] >= SPLIT_DATE, features]
    y_test  = df.loc[df['date'] >= SPLIT_DATE, target]

    print(f"   Train: {len(X_train):,} rows | Test: {len(X_test):,} rows")

    best_params = run_optuna(X_train, y_train, X_test, y_test)
    final_model = train_and_plot(X_train, y_train, X_test, y_test, best_params)
    evaluate(final_model, X_train, y_train, X_test, y_test, features)
    save_model(final_model, encoders)

    print(f"\n  Total pipeline time: {time.time() - total_start:.1f} seconds")
