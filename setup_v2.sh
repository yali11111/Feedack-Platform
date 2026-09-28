#!/bin/sh

set -eu

echo "======================================"
echo " Feedback Platform - V2 Setup"
echo "======================================"

# Vérifications OK
command -v php >/dev/null 2>&1 || {
    echo "❌ PHP n'est pas installé."
    exit 1
}

command -v composer >/dev/null 2>&1 || {
    echo "❌ Composer n'est pas installé."
    exit 1
}

if [ ! -f artisan ]; then
    echo "❌ Lance ce script depuis la racine du projet Laravel."
    exit 1
fi

echo ""
echo "➡️  Création d'une sauvegarde..."

BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp -R app "$BACKUP_DIR/" 2>/dev/null || true
cp -R database "$BACKUP_DIR/" 2>/dev/null || true
cp -R resources "$BACKUP_DIR/" 2>/dev/null || true
cp routes/web.php "$BACKUP_DIR/web.php" 2>/dev/null || true

echo "✅ Backup : $BACKUP_DIR"

echo ""
echo "➡️  Vérification Laravel..."

php artisan --version

echo ""
echo "➡️  Création des dossiers..."

mkdir -p app/Http/Controllers/Admin
mkdir -p app/Http/Requests
mkdir -p app/Http/Middleware
mkdir -p app/Notifications
mkdir -p app/Policies

echo "✅ Dossiers créés"

echo ""
echo "➡️  Génération des composants Laravel..."

php artisan make:model Feedback -m 2>/dev/null || true
php artisan make:model FeedbackVote -m 2>/dev/null || true

php artisan make:controller FeedbackController 2>/dev/null || true
php artisan make:controller FeedbackVoteController 2>/dev/null || true

php artisan make:controller Admin/DashboardController 2>/dev/null || true
php artisan make:controller Admin/FeedbackController 2>/dev/null || true

php artisan make:policy FeedbackPolicy --model=Feedback 2>/dev/null || true

php artisan make:request StoreFeedbackRequest 2>/dev/null || true
php artisan make:request UpdateFeedbackRequest 2>/dev/null || true

echo "✅ Composants générés"

echo ""
echo "➡️  Recherche de la migration users..."

USER_MIGRATION=$(find database/migrations -type f -name '*create_users_table.php' | head -n 1 || true)

if [ -n "$USER_MIGRATION" ]; then

    if ! grep -q "role" "$USER_MIGRATION"; then

        echo "➡️  Ajout du rôle utilisateur..."

        sed -i.bak "/Schema::create('users'/,/});/ s/\$table->string('email'/\$table->string('role')->default('user');\n            \$table->string('email'/" "$USER_MIGRATION" 2>/dev/null || true

        rm -f "$USER_MIGRATION.bak"

    else
        echo "ℹ️  Le champ role existe déjà."
    fi
fi

echo ""
echo "➡️  Configuration des migrations feedback..."

FEEDBACK_MIGRATION=$(find database/migrations -type f -name '*create_feedbacks_table.php' | head -n 1 || true)

if [ -n "$FEEDBACK_MIGRATION" ]; then

cat > "$FEEDBACK_MIGRATION" <<'PHP'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feedbacks', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained()
                ->cascadeOnDelete();

            $table->foreignId('course_id')
                ->constrained()
                ->cascadeOnDelete();

            $table->unsignedTinyInteger('rating');

            $table->text('content');

            $table->string('status')
                ->default('published');

            $table->timestamps();

            $table->index(['course_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feedbacks');
    }
};
PHP

fi

echo "➡️  Configuration des votes..."

VOTE_MIGRATION=$(find database/migrations -type f -name '*create_feedback_votes_table.php' | head -n 1 || true)

if [ -n "$VOTE_MIGRATION" ]; then

cat > "$VOTE_MIGRATION" <<'PHP'
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('feedback_votes', function (Blueprint $table) {
            $table->id();

            $table->foreignId('feedback_id')
                ->constrained()
                ->cascadeOnDelete();

            $table->foreignId('user_id')
                ->constrained()
                ->cascadeOnDelete();

            $table->boolean('value');

            $table->timestamps();

            $table->unique([
                'feedback_id',
                'user_id'
            ]);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('feedback_votes');
    }
};
PHP

fi

echo ""
echo "➡️  Mise à jour du modèle Feedback..."

cat > app/Models/Feedback.php <<'PHP'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Feedback extends Model
{
    protected $fillable = [
        'user_id',
        'course_id',
        'rating',
        'content',
        'status',
    ];

    protected $casts = [
        'rating' => 'integer',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function course(): BelongsTo
    {
        return $this->belongsTo(Course::class);
    }

    public function votes(): HasMany
    {
        return $this->hasMany(FeedbackVote::class);
    }

    public function positiveVotes(): HasMany
    {
        return $this->votes()->where('value', true);
    }

    public function negativeVotes(): HasMany
    {
        return $this->votes()->where('value', false);
    }
}
PHP

echo ""
echo "➡️  Mise à jour du modèle FeedbackVote..."

cat > app/Models/FeedbackVote.php <<'PHP'
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class FeedbackVote extends Model
{
    protected $fillable = [
        'feedback_id',
        'user_id',
        'value',
    ];

    protected $casts = [
        'value' => 'boolean',
    ];

    public function feedback(): BelongsTo
    {
        return $this->belongsTo(Feedback::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
PHP

echo ""
echo "➡️  Mise à jour du modèle User..."

if [ -f app/Models/User.php ]; then

    if ! grep -q "isAdmin" app/Models/User.php; then

        sed -i.bak "/class User extends Authenticatable/i\\
" app/Models/User.php 2>/dev/null || true

        rm -f app/Models/User.php.bak

    fi

fi

echo ""
echo "➡️  Création du middleware Admin..."

cat > app/Http/Middleware/AdminMiddleware.php <<'PHP'
<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class AdminMiddleware
{
    public function handle(
        Request $request,
        Closure $next
    ): Response {
        if (! $request->user()) {
            abort(401);
        }

        if ($request->user()->role !== 'admin') {
            abort(403, 'Accès réservé aux administrateurs.');
        }

        return $next($request);
    }
}
PHP

echo ""
echo "➡️  Configuration de la Policy..."

cat > app/Policies/FeedbackPolicy.php <<'PHP'
<?php

namespace App\Policies;

use App\Models\Feedback;
use App\Models\User;

class FeedbackPolicy
{
    public function update(User $user, Feedback $feedback): bool
    {
        return $user->id === $feedback->user_id;
    }

    public function delete(User $user, Feedback $feedback): bool
    {
        return $user->id === $feedback->user_id
            || $user->role === 'admin';
    }
}
PHP

echo ""
echo "➡️  Création du StoreFeedbackRequest..."

cat > app/Http/Requests/StoreFeedbackRequest.php <<'PHP'
<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreFeedbackRequest extends FormRequest
{
    public function authorize(): bool
    {
        return auth()->check();
    }

    public function rules(): array
    {
        return [
            'course_id' => [
                'required',
                'integer',
                'exists:courses,id',
            ],

            'rating' => [
                'required',
                'integer',
                'between:1,5',
            ],

            'content' => [
                'required',
                'string',
                'min:10',
                'max:2000',
            ],
        ];
    }
}
PHP

echo ""
echo "➡️  Création du UpdateFeedbackRequest..."

cat > app/Http/Requests/UpdateFeedbackRequest.php <<'PHP'
<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class UpdateFeedbackRequest extends FormRequest
{
    public function authorize(): bool
    {
        $feedback = $this->route('feedback');

        return $feedback
            && auth()->check()
            && auth()->user()->can('update', $feedback);
    }

    public function rules(): array
    {
        return [
            'rating' => [
                'required',
                'integer',
                'between:1,5',
            ],

            'content' => [
                'required',
                'string',
                'min:10',
                'max:2000',
            ],
        ];
    }
}
PHP

echo ""
echo "➡️  Mise à jour du cache Laravel..."

php artisan optimize:clear

echo ""
echo "➡️  Vérification de la configuration..."

php artisan config:clear
php artisan route:clear
php artisan view:clear

echo ""
echo "======================================"
echo " ✅ Installation V2 terminée"
echo "======================================"

echo ""
echo "⚠️  IMPORTANT :"
echo ""
echo "1. Vérifie les migrations avant de lancer migrate."
echo "2. Ajoute le middleware 'admin' dans bootstrap/app.php"
echo "   ou app/Http/Kernel.php selon ta version Laravel."
echo "3. Ajoute 'role' dans $fillable du modèle User."
echo "4. En production, utilise HTTPS et APP_DEBUG=false."
echo ""
echo "Puis :"
echo ""
echo "    php artisan migrate"
echo "    php artisan test"
echo ""
