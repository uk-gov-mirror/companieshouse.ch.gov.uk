package ChGovUk::Controllers::PersonalAppointments;

use Mojo::Base 'Mojolicious::Controller';

use CH::Perl;
use CH::Util::Pager;

use constant AVAILABLE_CATEGORIES => {
    active => 'Current appointments',
};

# ------------------------------------------------------------------------------

sub get {
    my ($self) = @_;

    $self->render_later;

    my $officer_id     = $self->param('officer_id');
    my $page           = abs int($self->param('page') || 1);
    my $items_per_page = $self->config->{officer_appointments}->{items_per_page} || 10;
    my $absolute_page  = abs int($page == 1 ? 0 : ($page - 1) * $items_per_page);

    my $pager = CH::Util::Pager->new(
        current_page     => $page,
        entries_per_page => $items_per_page,
    );

    # List of categories to filter by (optional)
    my @filters = split ',', $self->get_filter('oa');

    # Generate an arrayref containing hashrefs of category ids/names that are sorted by name
    my @categories = sort _sort_filter map { _build_filter($_) } keys %{ AVAILABLE_CATEGORIES() };

    # Iterate through categories setting checked flag
    for my $category (@categories) {
        $category->{checked} = 1 if grep { $category->{id} eq $_ } @filters;
    }

    my $filter = join ',', map { $_->{id} } grep { $_->{checked} } @categories;

    trace 'Fetching appointments page [%s] for officer [%s]', $page, $officer_id;

    $self->ch_api->officers($officer_id)->appointments({
        filter         => $filter,
        items_per_page => $items_per_page,
        start_index    => $absolute_page,
    })->get->on(
        success => sub {
            my ($api, $tx) = @_;

            my $results = $tx->success->json;
            trace 'Appointments for officer [%s]: %s', $officer_id, d:$results;

            my $officer = {
                appointments    => $results->{items},
                date_of_birth   => $results->{date_of_birth},
                name            => $results->{name},
                total_results   => $results->{total_results},
            };

            $pager->total_entries($results->{total_results});
            trace 'Total appointments [%d] with [%d] entries per page', $pager->total_entries, $pager->entries_per_page;

            my $paging = {
                current_page_number => $pager->current_page,
                page_set            => $pager->pages_in_set,
                next_page           => $pager->next_page,
                previous_page       => $pager->previous_page,
                entries_per_page    => $pager->entries_per_page,
            };

            # If the filter string contains 'active' we are assuming
            # the active filter is set. If is_active_filter_set then we
            # supress the resigned_count on template.
            my $is_active_filter_set = $filter =~ m/active/ ? 1 : 0;

            $self->stash(
                categories           => \@categories,
                is_active_filter_set => $is_active_filter_set,
                officer              => $officer,
                paging               => $paging,
            );

            return $self->render;
        },
        failure => sub {
            my ($api, $tx) = @_;

            my ($error_code, $error_message) = @{ $tx->error }{qw(code message)};

            if ($error_code and $error_code == 404) {
                trace 'Appointments not found for officer [%s]', $officer_id;
                return $self->render_not_found;
            }

            error 'Failed to retrieve appointments for officer [%s]: [%s]', $officer_id, $error_message;
            return $self->render_exception("Failed to retrieve officer appointments: $error_message");
        },
        error => sub {
            my ($api, $error) = @_;

            error 'Error retrieving appointments for officer [%s]: [%s]', $officer_id, $error;
            return $self->render_exception("Error retrieving officer appointments: $error");
        },
    )->execute;
}

# ------------------------------------------------------------------------------

sub _sort_filter {
    $a->{name} cmp $b->{name};
}

# ------------------------------------------------------------------------------

sub _build_filter {
    my ($filter) = @_;

    return {
        id   => $filter,
        name => AVAILABLE_CATEGORIES->{$filter},
    };
}

# ==============================================================================

1;
